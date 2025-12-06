defmodule NsaiRegistry.Storage.ETS do
  @moduledoc """
  ETS-based storage backend for service registry.

  Provides fast, in-memory storage with automatic cleanup on application restart.
  Suitable for development and single-node deployments.
  """

  @behaviour NsaiRegistry.Storage.Behaviour

  alias NsaiRegistry.Service

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :nsai_registry)

    table =
      :ets.new(table_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl true
  def register(state, %Service{} = service) do
    service_id = Service.id(service)
    :ets.insert(state.table, {service_id, service})
    {:ok, state}
  end

  @impl true
  def deregister(state, service_id) do
    :ets.delete(state.table, service_id)
    {:ok, state}
  end

  @impl true
  def lookup(state, service_name) do
    {:ok, services} = lookup_all(state, service_name)

    case services do
      [service | _] -> {:ok, service}
      [] -> {:ok, nil}
    end
  end

  @impl true
  def lookup_all(state, service_name) do
    services =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, service} -> service end)
      |> Enum.filter(fn service -> service.name == service_name end)

    {:ok, services}
  end

  @impl true
  def list_all(state) do
    services =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, service} -> service end)

    {:ok, services}
  end

  @impl true
  def update_status(state, service_id, status) do
    case :ets.lookup(state.table, service_id) do
      [{^service_id, service}] ->
        updated_service = Service.update_status(service, status)
        :ets.insert(state.table, {service_id, updated_service})
        {:ok, state}

      [] ->
        {:error, :service_not_found}
    end
  end
end
