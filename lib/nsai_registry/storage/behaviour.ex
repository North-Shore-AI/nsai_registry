defmodule NsaiRegistry.Storage.Behaviour do
  @moduledoc """
  Behaviour for service registry storage backends.

  Defines the contract for storing and retrieving service registrations.
  Implementations include ETS (in-memory) and Postgres (persistent).
  """

  alias NsaiRegistry.Service

  @doc """
  Initializes the storage backend.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Registers a service.
  """
  @callback register(state :: term(), service :: Service.t()) ::
              {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Deregisters a service by ID.
  """
  @callback deregister(state :: term(), service_id :: String.t()) ::
              {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Looks up a service by name (returns first match).
  """
  @callback lookup(state :: term(), service_name :: String.t()) ::
              {:ok, Service.t() | nil} | {:error, reason :: term()}

  @doc """
  Looks up all services by name.
  """
  @callback lookup_all(state :: term(), service_name :: String.t()) ::
              {:ok, [Service.t()]} | {:error, reason :: term()}

  @doc """
  Lists all registered services.
  """
  @callback list_all(state :: term()) :: {:ok, [Service.t()]} | {:error, reason :: term()}

  @doc """
  Updates a service status.
  """
  @callback update_status(state :: term(), service_id :: String.t(), status :: Service.status()) ::
              {:ok, state :: term()} | {:error, reason :: term()}
end
