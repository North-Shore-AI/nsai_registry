defmodule NsaiRegistry.HealthCheck.TCP do
  @moduledoc """
  TCP-based health checking for services.

  Performs basic TCP connection tests to verify service availability.
  """

  @doc """
  Performs a TCP health check by attempting to establish a connection.

  Returns `:ok` if connection succeeds, `{:error, reason}` otherwise.
  """
  @spec check(String.t(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def check(host, port, timeout) do
    host_charlist = String.to_charlist(host)

    case :gen_tcp.connect(host_charlist, port, [:binary, active: false], timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
