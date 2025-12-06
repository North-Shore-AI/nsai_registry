defmodule NsaiRegistry.HealthCheck.GRPC do
  @moduledoc """
  gRPC health checking for services.

  Implements the standard gRPC health checking protocol:
  https://github.com/grpc/grpc/blob/master/doc/health-checking.md

  Note: This is a basic implementation that uses HTTP/2 to check the
  gRPC health endpoint. For full gRPC support, you would need a gRPC
  client library.
  """

  @doc """
  Performs a gRPC health check using the standard health checking protocol.

  This is a simplified implementation that attempts an HTTP/2 connection
  to the gRPC health endpoint.
  """
  @spec check(String.t(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def check(host, port, timeout) do
    # gRPC health check endpoint
    url = "http://#{host}:#{port}/grpc.health.v1.Health/Check"

    case Req.post(url,
           headers: [
             {"content-type", "application/grpc"},
             {"te", "trailers"}
           ],
           receive_timeout: timeout,
           retry: false
         ) do
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
end
