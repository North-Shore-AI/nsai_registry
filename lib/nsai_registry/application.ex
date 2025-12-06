defmodule NsaiRegistry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration
    registry_config = Application.get_env(:nsai_registry, NsaiRegistry.Registry, [])
    health_checker_config = Application.get_env(:nsai_registry, NsaiRegistry.HealthChecker, [])

    children = [
      # PubSub for event broadcasting
      NsaiRegistry.PubSub,

      # Core registry GenServer
      {NsaiRegistry.Registry, registry_config},

      # Health checker worker
      {NsaiRegistry.HealthChecker, health_checker_config}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NsaiRegistry.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
