defmodule NsaiRegistry.Registry do
  @moduledoc """
  Core GenServer for service registration and discovery.

  Manages service lifecycle (register, deregister, lookup) and delegates
  storage to pluggable backends (ETS, Postgres).

  ## Configuration

      config :nsai_registry, NsaiRegistry.Registry,
        storage_backend: NsaiRegistry.Storage.ETS,
        storage_opts: [table_name: :nsai_registry]
  """

  use GenServer
  require Logger

  alias NsaiRegistry.{Service, PubSub, Telemetry}

  @default_backend NsaiRegistry.Storage.ETS

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a service.

  ## Examples

      iex> NsaiRegistry.Registry.register(%{
      ...>   name: "work",
      ...>   host: "localhost",
      ...>   port: 4000,
      ...>   protocol: :http,
      ...>   health_check: "/health"
      ...> })
      {:ok, %NsaiRegistry.Service{}}
  """
  def register(attrs) do
    GenServer.call(__MODULE__, {:register, attrs})
  end

  @doc """
  Deregisters a service by ID.
  """
  def deregister(service_id) do
    GenServer.call(__MODULE__, {:deregister, service_id})
  end

  @doc """
  Looks up a service by name (returns first match).
  """
  def lookup(service_name) do
    GenServer.call(__MODULE__, {:lookup, service_name})
  end

  @doc """
  Looks up a service by ID.
  """
  def lookup_by_id(service_id) do
    GenServer.call(__MODULE__, {:lookup_by_id, service_id})
  end

  @doc """
  Looks up all services by name.
  """
  def lookup_all(service_name) do
    GenServer.call(__MODULE__, {:lookup_all, service_name})
  end

  @doc """
  Lists all registered services.
  """
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Updates a service status.
  """
  def update_status(service_id, status) do
    GenServer.call(__MODULE__, {:update_status, service_id, status})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    backend = Keyword.get(opts, :storage_backend, @default_backend)
    storage_opts = Keyword.get(opts, :storage_opts, [])

    case backend.init(storage_opts) do
      {:ok, storage_state} ->
        state = %{
          backend: backend,
          storage_state: storage_state
        }

        Logger.info("NsaiRegistry started with backend: #{inspect(backend)}")
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:register, attrs}, _from, state) do
    Telemetry.register(
      fn ->
        with {:ok, service} <- Service.new(attrs),
             {:ok, storage_state} <- state.backend.register(state.storage_state, service) do
          PubSub.broadcast_registered(service)

          Logger.info("Registered service: #{service.name} at #{Service.url(service)}")

          {:reply, {:ok, service}, %{state | storage_state: storage_state}}
        else
          {:error, reason} = error ->
            Logger.error("Failed to register service: #{inspect(reason)}")
            {:reply, error, state}
        end
      end,
      %{service_name: attrs[:name]}
    )
  end

  @impl true
  def handle_call({:deregister, service_id}, _from, state) do
    Telemetry.deregister(
      fn ->
        # Get service name before deregistering for event broadcasting
        service_name =
          case lookup_by_id_internal(service_id, state) do
            {:ok, service} -> service.name
            _ -> "unknown"
          end

        case state.backend.deregister(state.storage_state, service_id) do
          {:ok, storage_state} ->
            PubSub.broadcast_deregistered(service_id, service_name)

            Logger.info("Deregistered service: #{service_id}")

            {:reply, :ok, %{state | storage_state: storage_state}}

          {:error, reason} = error ->
            Logger.error("Failed to deregister service #{service_id}: #{inspect(reason)}")
            {:reply, error, state}
        end
      end,
      %{service_id: service_id}
    )
  end

  @impl true
  def handle_call({:lookup, service_name}, _from, state) do
    Telemetry.lookup(
      fn ->
        result = state.backend.lookup(state.storage_state, service_name)
        {:reply, result, state}
      end,
      %{service_name: service_name}
    )
  end

  @impl true
  def handle_call({:lookup_by_id, service_id}, _from, state) do
    result = lookup_by_id_internal(service_id, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:lookup_all, service_name}, _from, state) do
    Telemetry.lookup(
      fn ->
        result = state.backend.lookup_all(state.storage_state, service_name)
        {:reply, result, state}
      end,
      %{service_name: service_name}
    )
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    result = state.backend.list_all(state.storage_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_status, service_id, new_status}, _from, state) do
    # Get old status for event broadcasting
    old_status =
      case lookup_by_id_internal(service_id, state) do
        {:ok, service} -> service.status
        _ -> :unknown
      end

    case state.backend.update_status(state.storage_state, service_id, new_status) do
      {:ok, storage_state} ->
        # Fetch updated service for broadcasting
        case lookup_by_id_internal(service_id, %{state | storage_state: storage_state}) do
          {:ok, service} ->
            if old_status != new_status do
              PubSub.broadcast_status_changed(service, old_status)

              Telemetry.status_change(%{
                service_id: service_id,
                service_name: service.name,
                old_status: old_status,
                new_status: new_status
              })

              Logger.info("Service #{service.name} status: #{old_status} -> #{new_status}")
            end

          _ ->
            :ok
        end

        {:reply, :ok, %{state | storage_state: storage_state}}

      {:error, reason} = error ->
        Logger.error("Failed to update status for #{service_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  # Private functions

  defp lookup_by_id_internal(service_id, state) do
    case state.backend.list_all(state.storage_state) do
      {:ok, services} ->
        case Enum.find(services, fn s -> Service.id(s) == service_id end) do
          nil -> {:error, :not_found}
          service -> {:ok, service}
        end

      error ->
        error
    end
  end
end
