defmodule NsaiRegistry.MixProject do
  use Mix.Project

  def project do
    [
      app: :nsai_registry,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {NsaiRegistry.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.4"},
      {:postgrex, "~> 0.17", optional: true},
      {:ecto_sql, "~> 3.10", optional: true}
    ]
  end
end
