defmodule Mix.Tasks.NsaiRegistry.List do
  @moduledoc """
  Lists all registered services.

  ## Usage

      mix nsai_registry.list
  """
  @shortdoc "Lists all registered services"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case NsaiRegistry.list_all() do
      {:ok, []} ->
        Mix.shell().info("No services registered.")

      {:ok, services} ->
        Mix.shell().info("\nRegistered Services:")
        Mix.shell().info(String.duplicate("=", 80))

        Enum.each(services, fn service ->
          Mix.shell().info("""
          Name:         #{service.name}
          URL:          #{NsaiRegistry.Service.url(service)}
          Status:       #{service.status}
          Registered:   #{service.registered_at}
          Last Check:   #{service.last_check || "Never"}
          Metadata:     #{inspect(service.metadata)}
          #{String.duplicate("-", 80)}
          """)
        end)

      {:error, reason} ->
        Mix.shell().error("Failed to list services: #{inspect(reason)}")
    end
  end
end

defmodule Mix.Tasks.NsaiRegistry.Register do
  @moduledoc """
  Registers a new service.

  ## Usage

      mix nsai_registry.register NAME HOST PORT [OPTIONS]

  ## Options

      --protocol PROTOCOL    Protocol (http, https, tcp, grpc) [default: http]
      --health-check PATH    Health check endpoint path
      --metadata KEY=VALUE   Add metadata (can be used multiple times)

  ## Examples

      mix nsai_registry.register work localhost 4000 --health-check /health
      mix nsai_registry.register api api.example.com 443 --protocol https
  """
  @shortdoc "Registers a new service"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [protocol: :string, health_check: :string, metadata: :keep_string]
      )

    case args do
      [name, host, port] ->
        attrs = %{
          name: name,
          host: host,
          port: String.to_integer(port),
          protocol: parse_protocol(opts[:protocol]),
          health_check: opts[:health_check],
          metadata: parse_metadata(opts[:metadata] || [])
        }

        case NsaiRegistry.register(attrs) do
          {:ok, service} ->
            Mix.shell().info("Service registered successfully!")
            Mix.shell().info("ID: #{NsaiRegistry.Service.id(service)}")
            Mix.shell().info("URL: #{NsaiRegistry.Service.url(service)}")

          {:error, reason} ->
            Mix.shell().error("Failed to register service: #{inspect(reason)}")
        end

      _ ->
        Mix.shell().error("Usage: mix nsai_registry.register NAME HOST PORT [OPTIONS]")
    end
  end

  defp parse_protocol(nil), do: :http
  defp parse_protocol("http"), do: :http
  defp parse_protocol("https"), do: :https
  defp parse_protocol("tcp"), do: :tcp
  defp parse_protocol("grpc"), do: :grpc
  defp parse_protocol(other), do: String.to_atom(other)

  defp parse_metadata(metadata_list) do
    Enum.reduce(metadata_list, %{}, fn kv, acc ->
      case String.split(kv, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
  end
end

defmodule Mix.Tasks.NsaiRegistry.Deregister do
  @moduledoc """
  Deregisters a service by ID.

  ## Usage

      mix nsai_registry.deregister SERVICE_ID

  ## Examples

      mix nsai_registry.deregister work:localhost:4000
  """
  @shortdoc "Deregisters a service"

  use Mix.Task

  @impl Mix.Task
  def run([service_id]) do
    Mix.Task.run("app.start")

    case NsaiRegistry.deregister(service_id) do
      :ok ->
        Mix.shell().info("Service deregistered successfully!")

      {:error, reason} ->
        Mix.shell().error("Failed to deregister service: #{inspect(reason)}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix nsai_registry.deregister SERVICE_ID")
  end
end

defmodule Mix.Tasks.NsaiRegistry.HealthCheck do
  @moduledoc """
  Triggers a health check for all services or a specific service.

  ## Usage

      mix nsai_registry.health_check [SERVICE_ID]

  ## Examples

      # Check all services
      mix nsai_registry.health_check

      # Check specific service
      mix nsai_registry.health_check work:localhost:4000
  """
  @shortdoc "Triggers health checks"

  use Mix.Task

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("app.start")
    Mix.shell().info("Triggering health check for all services...")
    NsaiRegistry.HealthChecker.check_now()
    Mix.shell().info("Health check initiated. Check logs for results.")
  end

  def run([service_id]) do
    Mix.Task.run("app.start")
    Mix.shell().info("Triggering health check for #{service_id}...")
    NsaiRegistry.HealthChecker.check_service(service_id)
    Mix.shell().info("Health check initiated. Check logs for results.")
  end
end
