defmodule NsaiRegistry.Service do
  @moduledoc """
  Service registration struct for NSAI ecosystem.

  Represents a service instance with connection details, health check configuration,
  and metadata.
  """

  @type protocol :: :http | :https | :tcp | :grpc
  @type status :: :healthy | :unhealthy | :unknown

  @type t :: %__MODULE__{
          name: String.t(),
          host: String.t(),
          port: pos_integer(),
          protocol: protocol(),
          health_check: String.t() | nil,
          metadata: map(),
          status: status(),
          registered_at: DateTime.t(),
          last_check: DateTime.t() | nil
        }

  @derive Jason.Encoder
  defstruct [
    :name,
    :host,
    :port,
    :protocol,
    :health_check,
    :metadata,
    :status,
    :registered_at,
    :last_check
  ]

  @doc """
  Creates a new service registration.

  ## Examples

      iex> NsaiRegistry.Service.new(%{
      ...>   name: "work",
      ...>   host: "localhost",
      ...>   port: 4000,
      ...>   protocol: :http,
      ...>   health_check: "/health"
      ...> })
      {:ok, %NsaiRegistry.Service{}}

      iex> NsaiRegistry.Service.new(%{name: "work"})
      {:error, :missing_required_fields}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_protocol(attrs[:protocol]) do
      service = %__MODULE__{
        name: attrs[:name],
        host: attrs[:host],
        port: attrs[:port],
        protocol: attrs[:protocol] || :http,
        health_check: attrs[:health_check],
        metadata: attrs[:metadata] || %{},
        status: :unknown,
        registered_at: DateTime.utc_now(),
        last_check: nil
      }

      {:ok, service}
    end
  end

  @doc """
  Generates a unique service ID based on name, host, and port.
  """
  @spec id(t()) :: String.t()
  def id(%__MODULE__{name: name, host: host, port: port}) do
    "#{name}:#{host}:#{port}"
  end

  @doc """
  Returns the base URL for the service.
  """
  @spec url(t()) :: String.t()
  def url(%__MODULE__{protocol: protocol, host: host, port: port}) do
    "#{protocol}://#{host}:#{port}"
  end

  @doc """
  Returns the full health check URL if configured.
  """
  @spec health_check_url(t()) :: String.t() | nil
  def health_check_url(%__MODULE__{health_check: nil}), do: nil

  def health_check_url(%__MODULE__{} = service) do
    "#{url(service)}#{service.health_check}"
  end

  @doc """
  Updates the service status.
  """
  @spec update_status(t(), status()) :: t()
  def update_status(%__MODULE__{} = service, status)
      when status in [:healthy, :unhealthy, :unknown] do
    %{service | status: status, last_check: DateTime.utc_now()}
  end

  # Private functions

  defp validate_required(attrs) do
    required_fields = [:name, :host, :port]

    if Enum.all?(required_fields, &Map.has_key?(attrs, &1)) do
      :ok
    else
      {:error, :missing_required_fields}
    end
  end

  defp validate_protocol(nil), do: :ok
  defp validate_protocol(protocol) when protocol in [:http, :https, :tcp, :grpc], do: :ok
  defp validate_protocol(_), do: {:error, :invalid_protocol}
end
