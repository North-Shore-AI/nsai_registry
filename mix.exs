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
      # Core dependencies
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.4"},

      # Optional storage backends
      {:postgrex, "~> 0.17", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},

      # Distributed features
      {:horde, "~> 0.9", optional: true},
      {:libring, "~> 1.6"},

      # Development and testing
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end
