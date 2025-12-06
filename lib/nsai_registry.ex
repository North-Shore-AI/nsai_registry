defmodule NsaiRegistry do
  @moduledoc """
  Service discovery and registry for the NSAI ecosystem.

  NsaiRegistry provides a lightweight, pluggable service registry with health checking,
  event broadcasting, and telemetry integration. Services can register themselves,
  discover other services, and receive notifications about topology changes.

  ## Features

  - Service registration and discovery
  - Automatic health checking with configurable intervals
  - Event broadcasting via PubSub
  - Telemetry integration for observability
  - Pluggable storage backends (ETS, Postgres)
  - Load balancing support via lookup_all

  ## Quick Start

      # Register a service
      {:ok, service} = NsaiRegistry.register(%{
        name: "work",
        host: "localhost",
        port: 4000,
        protocol: :http,
        health_check: "/health",
        metadata: %{version: "0.1.0"}
      })

      # Discover a service
      {:ok, service} = NsaiRegistry.lookup("work")

      # Subscribe to events
      NsaiRegistry.PubSub.subscribe()

      receive do
        {:service_registered, svc} ->
          IO.puts("New service: " <> svc.name)
      end

  ## Configuration

      config :nsai_registry, NsaiRegistry.Registry,
        storage_backend: NsaiRegistry.Storage.ETS,
        storage_opts: [table_name: :nsai_registry]

      config :nsai_registry, NsaiRegistry.HealthChecker,
        check_interval: 30_000,
        timeout: 5_000,
        auto_deregister: false,
        unhealthy_threshold: 3
  """

  alias NsaiRegistry.Registry

  @doc """
  Registers a service.

  ## Parameters

  - `attrs` - Map with the following keys:
    - `:name` (required) - Service name (e.g., "work", "forge")
    - `:host` (required) - Hostname or IP address
    - `:port` (required) - Port number
    - `:protocol` - Protocol (`:http`, `:https`, `:tcp`, `:grpc`), defaults to `:http`
    - `:health_check` - Health check endpoint path (e.g., "/health")
    - `:metadata` - Additional metadata map

  ## Examples

      iex> NsaiRegistry.register(%{
      ...>   name: "work",
      ...>   host: "localhost",
      ...>   port: 4000,
      ...>   health_check: "/health"
      ...> })
      {:ok, %NsaiRegistry.Service{}}
  """
  defdelegate register(attrs), to: Registry

  @doc """
  Deregisters a service by ID.

  ## Examples

      iex> NsaiRegistry.deregister("work:localhost:4000")
      :ok
  """
  defdelegate deregister(service_id), to: Registry

  @doc """
  Looks up a service by name (returns first match).

  ## Examples

      iex> NsaiRegistry.lookup("work")
      {:ok, %NsaiRegistry.Service{}}

      iex> NsaiRegistry.lookup("nonexistent")
      {:ok, nil}
  """
  defdelegate lookup(service_name), to: Registry

  @doc """
  Looks up a service by ID.

  ## Examples

      iex> NsaiRegistry.lookup_by_id("work:localhost:4000")
      {:ok, %NsaiRegistry.Service{}}
  """
  defdelegate lookup_by_id(service_id), to: Registry

  @doc """
  Looks up all services by name.

  Useful for load balancing - returns all registered instances of a service.

  ## Examples

      iex> NsaiRegistry.lookup_all("work")
      {:ok, [%NsaiRegistry.Service{}, %NsaiRegistry.Service{}]}
  """
  defdelegate lookup_all(service_name), to: Registry

  @doc """
  Lists all registered services.

  ## Examples

      iex> NsaiRegistry.list_all()
      {:ok, [%NsaiRegistry.Service{}, ...]}
  """
  defdelegate list_all(), to: Registry

  @doc """
  Updates a service status.

  ## Examples

      iex> NsaiRegistry.update_status("work:localhost:4000", :healthy)
      :ok
  """
  defdelegate update_status(service_id, status), to: Registry
end
