defmodule NsaiRegistry.Storage.Postgres do
  @moduledoc """
  Postgres-based storage backend for service registry.

  Provides persistent storage suitable for production deployments and
  multi-node clusters. Requires Ecto and Postgrex dependencies.

  ## Configuration

      config :nsai_registry, NsaiRegistry.Storage.Postgres,
        repo: MyApp.Repo

  ## Migration

  Run the migration to create the services table:

      mix ecto.gen.migration create_services
      # Copy migration from priv/repo/migrations/create_services.exs.template
      mix ecto.migrate
  """

  @behaviour NsaiRegistry.Storage.Behaviour

  require Logger

  alias NsaiRegistry.Service
  alias NsaiRegistry.Storage.Postgres.Schema

  import Ecto.Query

  @impl true
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)

    # Validate repo is started and table exists
    case validate_setup(repo) do
      :ok ->
        {:ok, %{repo: repo}}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def register(state, %Service{} = service) do
    changeset = Schema.from_service(service)

    case state.repo.insert(
           changeset,
           on_conflict: {:replace, [:status, :last_check, :metadata]},
           conflict_target: :id
         ) do
      {:ok, _schema} ->
        {:ok, state}

      {:error, changeset} ->
        Logger.error("Failed to register service: #{inspect(changeset.errors)}")
        {:error, :insert_failed}
    end
  end

  @impl true
  def deregister(state, service_id) do
    {_count, _} = state.repo.delete_all(from(s in Schema, where: s.id == ^service_id))
    {:ok, state}
  rescue
    exception ->
      Logger.error("Failed to deregister service: #{inspect(exception)}")
      {:error, :delete_failed}
  end

  @impl true
  def lookup(state, service_name) do
    query =
      from(s in Schema,
        where: s.name == ^service_name,
        limit: 1
      )

    case state.repo.one(query) do
      nil ->
        {:ok, nil}

      schema ->
        service = Schema.to_service(schema)
        {:ok, service}
    end
  rescue
    exception ->
      Logger.error("Failed to lookup service: #{inspect(exception)}")
      {:error, :lookup_failed}
  end

  @impl true
  def lookup_all(state, service_name) do
    query =
      from(s in Schema,
        where: s.name == ^service_name,
        order_by: [asc: s.registered_at]
      )

    schemas = state.repo.all(query)
    services = Enum.map(schemas, &Schema.to_service/1)
    {:ok, services}
  rescue
    exception ->
      Logger.error("Failed to lookup services: #{inspect(exception)}")
      {:error, :lookup_failed}
  end

  @impl true
  def list_all(state) do
    schemas = state.repo.all(Schema)
    services = Enum.map(schemas, &Schema.to_service/1)
    {:ok, services}
  rescue
    exception ->
      Logger.error("Failed to list services: #{inspect(exception)}")
      {:error, :list_failed}
  end

  @impl true
  def update_status(state, service_id, status) do
    query = from(s in Schema, where: s.id == ^service_id)

    updates = [
      set: [
        status: to_string(status),
        last_check: DateTime.utc_now()
      ]
    ]

    case state.repo.update_all(query, updates) do
      {1, _} ->
        {:ok, state}

      {0, _} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Failed to update status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp validate_setup(repo) do
    # Check if repo is available
    try do
      repo.all(from(s in Schema, limit: 1))
      :ok
    rescue
      Ecto.QueryError ->
        {:error, :table_not_found}

      exception ->
        Logger.error("Postgres setup validation failed: #{inspect(exception)}")
        {:error, :repo_not_available}
    end
  end
end
