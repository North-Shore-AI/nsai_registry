defmodule NsaiRegistry.HealthChecker do
  @moduledoc """
  Periodic health checker for registered services.

  Runs background health checks on all registered services and automatically
  updates their status. Unhealthy services can be automatically deregistered
  based on configuration.

  ## Configuration

      config :nsai_registry, NsaiRegistry.HealthChecker,
        check_interval: 30_000,           # Check every 30 seconds
        timeout: 5_000,                   # 5 second timeout per check
        auto_deregister: false,           # Don't auto-remove unhealthy services
        unhealthy_threshold: 3            # Deregister after 3 consecutive failures
  """

  use GenServer
  require Logger

  alias NsaiRegistry.{Service, Telemetry}

  @default_check_interval 30_000
  @default_timeout 5_000
  @default_auto_deregister false
  @default_unhealthy_threshold 3

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate health check for all services.
  """
  @spec check_now() :: :ok
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  @doc """
  Triggers a health check for a specific service.
  """
  @spec check_service(String.t()) :: :ok
  def check_service(service_id) do
    GenServer.cast(__MODULE__, {:check_service, service_id})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    auto_deregister = Keyword.get(opts, :auto_deregister, @default_auto_deregister)
    unhealthy_threshold = Keyword.get(opts, :unhealthy_threshold, @default_unhealthy_threshold)

    state = %{
      check_interval: check_interval,
      timeout: timeout,
      auto_deregister: auto_deregister,
      unhealthy_threshold: unhealthy_threshold,
      failure_counts: %{}
    }

    # Schedule first check
    schedule_check(state.check_interval)

    {:ok, state}
  end

  @impl true
  def handle_cast(:check_now, state) do
    perform_health_checks(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:check_service, service_id}, state) do
    case NsaiRegistry.lookup_by_id(service_id) do
      {:ok, service} ->
        check_and_update_service(service, state)

      {:error, _} ->
        Logger.warning("Service #{service_id} not found for health check")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:perform_health_checks, state) do
    perform_health_checks(state)
    schedule_check(state.check_interval)
    {:noreply, state}
  end

  # Private functions

  defp schedule_check(interval) do
    Process.send_after(self(), :perform_health_checks, interval)
  end

  defp perform_health_checks(state) do
    case NsaiRegistry.list_all() do
      {:ok, services} ->
        Enum.each(services, fn service ->
          check_and_update_service(service, state)
        end)

      {:error, reason} ->
        Logger.error("Failed to list services for health check: #{inspect(reason)}")
    end
  end

  defp check_and_update_service(%Service{health_check: nil} = service, _state) do
    # No health check configured, assume healthy
    update_service_status(service, :healthy)
  end

  defp check_and_update_service(%Service{} = service, state) do
    service_id = Service.id(service)

    # Use circuit breaker if available
    result =
      if Process.whereis(NsaiRegistry.CircuitBreaker) do
        NsaiRegistry.CircuitBreaker.call(service_id, fn ->
          perform_health_check(service, state.timeout)
        end)
      else
        perform_health_check(service, state.timeout)
      end

    result =
      Telemetry.health_check(
        fn -> result end,
        %{service_id: service_id, service_name: service.name}
      )

    case result do
      :ok ->
        update_service_status(service, :healthy)

        {:noreply, %{state | failure_counts: Map.delete(state.failure_counts, service_id)}}

      {:error, :circuit_open} ->
        # Circuit breaker is open, skip this check
        Logger.debug("Skipping health check for #{service.name} - circuit breaker open")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Health check failed for #{service.name}: #{inspect(reason)}")
        handle_health_check_failure(service, state)
    end
  end

  defp perform_health_check(%Service{protocol: :http} = service, timeout) do
    health_check_url = Service.health_check_url(service)
    perform_http_check(health_check_url, timeout)
  end

  defp perform_health_check(%Service{protocol: :https} = service, timeout) do
    health_check_url = Service.health_check_url(service)
    perform_http_check(health_check_url, timeout)
  end

  defp perform_health_check(%Service{protocol: :tcp} = service, timeout) do
    NsaiRegistry.HealthCheck.TCP.check(service.host, service.port, timeout)
  end

  defp perform_health_check(%Service{protocol: :grpc} = service, timeout) do
    NsaiRegistry.HealthCheck.GRPC.check(service.host, service.port, timeout)
  end

  defp perform_http_check(url, timeout) do
    case Req.get(url, receive_timeout: timeout, retry: false) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:unhealthy_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception ->
      {:error, {:exception, exception}}
  end

  defp handle_health_check_failure(service, state) do
    service_id = Service.id(service)
    failure_count = Map.get(state.failure_counts, service_id, 0) + 1

    if failure_count >= state.unhealthy_threshold do
      update_service_status(service, :unhealthy)

      if state.auto_deregister do
        Logger.info("Auto-deregistering unhealthy service: #{service.name}")
        NsaiRegistry.deregister(service_id)
      end

      {:noreply, %{state | failure_counts: Map.delete(state.failure_counts, service_id)}}
    else
      {:noreply,
       %{state | failure_counts: Map.put(state.failure_counts, service_id, failure_count)}}
    end
  end

  defp update_service_status(service, new_status) do
    service_id = Service.id(service)

    if service.status != new_status do
      NsaiRegistry.update_status(service_id, new_status)
    end
  end
end
