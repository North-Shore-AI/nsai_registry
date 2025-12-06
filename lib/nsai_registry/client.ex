defmodule NsaiRegistry.Client do
  @moduledoc """
  Convenience client for integrating with NsaiRegistry.

  Provides high-level helpers for common patterns like:
  - Load balancing across service instances
  - Connection pooling
  - Automatic failover
  - Health-aware routing

  ## Examples

      # Get a random healthy service instance
      {:ok, service} = NsaiRegistry.Client.get_healthy("work")
      url = NsaiRegistry.Service.url(service)

      # Round-robin load balancing
      {:ok, service} = NsaiRegistry.Client.round_robin("work")

      # Get all healthy instances
      {:ok, services} = NsaiRegistry.Client.get_all_healthy("work")

      # Make a request with automatic failover
      {:ok, response} = NsaiRegistry.Client.call("work", fn service ->
        url = NsaiRegistry.Service.url(service)
        Req.get(url <> "/api/endpoint")
      end)
  """

  require Logger

  alias NsaiRegistry.Service

  @doc """
  Gets a random healthy service instance.

  Returns the first healthy service found, or falls back to any service
  if no healthy instances are available.
  """
  @spec get_healthy(String.t()) :: {:ok, Service.t()} | {:error, term()}
  def get_healthy(service_name) do
    with {:ok, services} <- NsaiRegistry.lookup_all(service_name),
         {:ok, service} <- select_healthy(services) do
      {:ok, service}
    end
  end

  @doc """
  Gets all healthy service instances.
  """
  @spec get_all_healthy(String.t()) :: {:ok, [Service.t()]} | {:error, term()}
  def get_all_healthy(service_name) do
    with {:ok, services} <- NsaiRegistry.lookup_all(service_name) do
      healthy = Enum.filter(services, &(&1.status == :healthy))

      if healthy == [] do
        # Fallback to all services if none are healthy
        {:ok, services}
      else
        {:ok, healthy}
      end
    end
  end

  @doc """
  Selects a service using round-robin load balancing.

  Uses a persistent counter stored in the process dictionary to track
  which instance to use next.
  """
  @spec round_robin(String.t()) :: {:ok, Service.t()} | {:error, term()}
  def round_robin(service_name) do
    with {:ok, services} <- get_all_healthy(service_name),
         {:ok, service} <- select_round_robin(service_name, services) do
      {:ok, service}
    end
  end

  @doc """
  Calls a function with a service, automatically retrying with other instances on failure.

  The function should return `{:ok, result}` on success or `{:error, reason}` on failure.
  Will attempt all available healthy instances before giving up.

  ## Options

  - `:max_retries` - Maximum number of retry attempts (default: 3)
  - `:retry_delay` - Milliseconds to wait between retries (default: 100)
  """
  @spec call(String.t(), (Service.t() -> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def call(service_name, fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 100)

    case get_all_healthy(service_name) do
      {:ok, services} when services != [] ->
        call_with_retry(services, fun, max_retries, retry_delay)

      {:ok, []} ->
        {:error, :no_services_available}

      error ->
        error
    end
  end

  @doc """
  Subscribes to events for a specific service and executes callbacks.

  ## Callbacks

  - `:on_registered` - Called when a new instance is registered
  - `:on_deregistered` - Called when an instance is deregistered
  - `:on_healthy` - Called when an instance becomes healthy
  - `:on_unhealthy` - Called when an instance becomes unhealthy

  ## Example

      NsaiRegistry.Client.watch("work",
        on_healthy: fn svc ->
          IO.puts("Service is now healthy!")
        end,
        on_unhealthy: fn svc ->
          IO.puts("Service is now unhealthy!")
        end
      )
  """
  @spec watch(String.t(), keyword()) :: :ok | {:error, term()}
  def watch(service_name, callbacks \\ []) do
    case NsaiRegistry.PubSub.subscribe(service_name) do
      :ok ->
        spawn(fn -> event_loop(callbacks) end)
        :ok

      error ->
        error
    end
  end

  # Private functions

  defp select_healthy([]), do: {:error, :no_services_available}

  defp select_healthy(services) do
    healthy = Enum.filter(services, &(&1.status == :healthy))

    service =
      case healthy do
        [] -> Enum.random(services)
        _ -> Enum.random(healthy)
      end

    {:ok, service}
  end

  defp select_round_robin(_service_name, []), do: {:error, :no_services_available}

  defp select_round_robin(service_name, services) do
    key = {:round_robin_counter, service_name}
    counter = Process.get(key, 0)
    index = rem(counter, length(services))
    Process.put(key, counter + 1)

    {:ok, Enum.at(services, index)}
  end

  defp call_with_retry([], _fun, _max_retries, _retry_delay) do
    {:error, :all_services_failed}
  end

  defp call_with_retry([service | rest], fun, max_retries, retry_delay) do
    case fun.(service) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.warning("Request to #{service.name} failed: #{inspect(reason)}")

        if max_retries > 0 and rest != [] do
          Process.sleep(retry_delay)
          call_with_retry(rest, fun, max_retries - 1, retry_delay)
        else
          {:error, reason}
        end
    end
  end

  defp event_loop(callbacks) do
    receive do
      {:service_registered, service} ->
        if callback = callbacks[:on_registered] do
          callback.(service)
        end

        event_loop(callbacks)

      {:service_deregistered, _service_id} ->
        if callback = callbacks[:on_deregistered] do
          callback.()
        end

        event_loop(callbacks)

      {:service_healthy, service} ->
        if callback = callbacks[:on_healthy] do
          callback.(service)
        end

        event_loop(callbacks)

      {:service_unhealthy, service} ->
        if callback = callbacks[:on_unhealthy] do
          callback.(service)
        end

        event_loop(callbacks)

      _ ->
        event_loop(callbacks)
    end
  end
end
