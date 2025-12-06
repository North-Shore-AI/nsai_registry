defmodule NsaiRegistry.Storage.Postgres.Schema do
  @moduledoc """
  Ecto schema for service registry entries in Postgres.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias NsaiRegistry.Service

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          host: String.t(),
          port: integer(),
          protocol: String.t(),
          health_check: String.t() | nil,
          metadata: map(),
          status: String.t(),
          registered_at: DateTime.t(),
          last_check: DateTime.t() | nil
        }

  @primary_key {:id, :string, []}
  schema "services" do
    field(:name, :string)
    field(:host, :string)
    field(:port, :integer)
    field(:protocol, :string)
    field(:health_check, :string)
    field(:metadata, :map)
    field(:status, :string)
    field(:registered_at, :utc_datetime)
    field(:last_check, :utc_datetime)
  end

  @doc """
  Converts a Service struct to a changeset for database insertion/update.
  """
  @spec from_service(Service.t()) :: Ecto.Changeset.t()
  def from_service(%Service{} = service) do
    service_id = Service.id(service)

    attrs = %{
      id: service_id,
      name: service.name,
      host: service.host,
      port: service.port,
      protocol: to_string(service.protocol),
      health_check: service.health_check,
      metadata: service.metadata,
      status: to_string(service.status),
      registered_at: service.registered_at,
      last_check: service.last_check
    }

    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :host,
      :port,
      :protocol,
      :health_check,
      :metadata,
      :status,
      :registered_at,
      :last_check
    ])
    |> validate_required([:id, :name, :host, :port, :protocol, :status, :registered_at])
  end

  @doc """
  Converts a database schema to a Service struct.
  """
  @spec to_service(t()) :: Service.t()
  def to_service(%__MODULE__{} = schema) do
    %Service{
      name: schema.name,
      host: schema.host,
      port: schema.port,
      protocol: String.to_existing_atom(schema.protocol),
      health_check: schema.health_check,
      metadata: schema.metadata || %{},
      status: String.to_existing_atom(schema.status),
      registered_at: schema.registered_at,
      last_check: schema.last_check
    }
  end
end
