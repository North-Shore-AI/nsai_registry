<p align="center">
  <img src="assets/nsai_registry.svg" alt="NSAI Registry" width="200">
</p>

<h1 align="center">NSAI Registry</h1>

<p align="center">
  <a href="https://github.com/North-Shore-AI/nsai_registry/actions"><img src="https://github.com/North-Shore-AI/nsai_registry/workflows/CI/badge.svg" alt="CI Status"></a>
  <a href="https://hex.pm/packages/nsai_registry"><img src="https://img.shields.io/hexpm/v/nsai_registry.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/nsai_registry"><img src="https://img.shields.io/badge/docs-hexdocs-blue.svg" alt="Documentation"></a>
  <img src="https://img.shields.io/badge/elixir-%3E%3D%201.14-purple.svg" alt="Elixir">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"></a>
</p>

<p align="center">
  Service discovery and registry for the NSAI ecosystem
</p>

---

A robust, production-ready service registry and discovery system for the NSAI (North Shore AI) ecosystem. Built with Elixir, it provides health checking, event broadcasting, multiple storage backends, and distributed clustering capabilities.

## Features

- **Service Registration & Discovery**: Register services and discover them by name with support for multiple instances
- **Health Checking**: Automatic health monitoring with support for HTTP, HTTPS, TCP, and gRPC protocols
- **Circuit Breaker**: Prevent cascading failures with built-in circuit breaker pattern
- **Event Broadcasting**: Real-time PubSub events for service topology changes
- **Multiple Storage Backends**: In-memory (ETS) for development, PostgreSQL for production
- **Load Balancing**: Built-in client with round-robin and health-aware routing
- **Telemetry**: Comprehensive instrumentation for monitoring and observability
- **Distributed Ready**: Optional Horde integration for multi-node clustering
- **CLI Management**: Mix tasks for service management

## Installation

Add `nsai_registry` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nsai_registry, "~> 0.1.0"},

    # Optional: For PostgreSQL backend
    {:postgrex, "~> 0.17"},
    {:ecto_sql, "~> 3.10"},

    # Optional: For distributed registry
    {:horde, "~> 0.9"}
  ]
end
```

## Quick Start

```elixir
# Register a service
{:ok, service} = NsaiRegistry.register(%{
  name: "work",
  host: "localhost",
  port: 4000,
  protocol: :http,
  health_check: "/health",
  metadata: %{version: "0.1.0"}
})

# Discover a service
{:ok, service} = NsaiRegistry.lookup("work")
url = NsaiRegistry.Service.url(service)

# Discover all instances (for load balancing)
{:ok, services} = NsaiRegistry.lookup_all("work")

# Subscribe to topology changes
NsaiRegistry.PubSub.subscribe()

receive do
  {:service_registered, svc} ->
    IO.puts("New service: #{svc.name}")
  {:service_healthy, svc} ->
    IO.puts("Service #{svc.name} is healthy")
end
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Client Applications                     │
└───────────────┬──────────────────────────────┬──────────────┘
                │                              │
                ▼                              ▼
┌───────────────────────────┐  ┌──────────────────────────────┐
│   NsaiRegistry.Client     │  │   NsaiRegistry (Main API)    │
│  - Load Balancing         │  │  - Register/Deregister       │
│  - Failover               │  │  - Lookup Services           │
│  - Health-Aware Routing   │  │  - Status Updates            │
└───────────────┬───────────┘  └───────────┬──────────────────┘
                │                          │
                └──────────┬───────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    NsaiRegistry.Registry                     │
│                      (GenServer Core)                        │
└───┬─────────────┬──────────────┬─────────────┬─────────────┘
    │             │              │             │
    ▼             ▼              ▼             ▼
┌─────────┐ ┌──────────┐ ┌────────────┐ ┌──────────────────┐
│ Storage │ │  PubSub  │ │ Telemetry  │ │ Health Checker   │
│ Backend │ │  Events  │ │ Metrics    │ │ - HTTP/TCP/gRPC  │
│ (ETS/PG)│ │          │ │            │ │ - Circuit Breaker│
└─────────┘ └──────────┘ └────────────┘ └──────────────────┘
```

## Configuration

### Basic Configuration

```elixir
# config/config.exs

# Registry configuration
config :nsai_registry, NsaiRegistry.Registry,
  storage_backend: NsaiRegistry.Storage.ETS,
  storage_opts: [table_name: :nsai_registry]

# Health checker configuration
config :nsai_registry, NsaiRegistry.HealthChecker,
  check_interval: 30_000,           # Check every 30 seconds
  timeout: 5_000,                   # 5 second timeout per check
  auto_deregister: false,           # Don't auto-remove unhealthy services
  unhealthy_threshold: 3            # Mark unhealthy after 3 consecutive failures

# Circuit breaker configuration
config :nsai_registry, NsaiRegistry.CircuitBreaker,
  failure_threshold: 5,             # Open circuit after 5 failures
  timeout: 60_000,                  # Wait 60s before testing recovery
  half_open_max_calls: 3            # Max calls in half-open state
```

### PostgreSQL Storage Backend

```elixir
# 1. Configure your Ecto repo
config :my_app, MyApp.Repo,
  database: "my_app_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10

# 2. Use Postgres backend
config :nsai_registry, NsaiRegistry.Registry,
  storage_backend: NsaiRegistry.Storage.Postgres,
  storage_opts: [repo: MyApp.Repo]

# 3. Run the migration
# Copy priv/repo/migrations/create_services.exs.template
# to your app and run: mix ecto.migrate
```

## Usage Examples

### Load Balancing with Client

```elixir
# Get a healthy service instance with automatic failover
{:ok, response} = NsaiRegistry.Client.call("work", fn service ->
  url = NsaiRegistry.Service.url(service)
  Req.post(url <> "/api/task", json: %{job: "process"})
end, max_retries: 3)

# Round-robin load balancing
{:ok, service} = NsaiRegistry.Client.round_robin("work")

# Get all healthy instances
{:ok, healthy_services} = NsaiRegistry.Client.get_all_healthy("work")
```

### Health Checking

```elixir
# HTTP/HTTPS health check (default)
NsaiRegistry.register(%{
  name: "api",
  host: "api.example.com",
  port: 443,
  protocol: :https,
  health_check: "/health"
})

# TCP health check
NsaiRegistry.register(%{
  name: "database",
  host: "db.example.com",
  port: 5432,
  protocol: :tcp
})

# gRPC health check
NsaiRegistry.register(%{
  name: "grpc-service",
  host: "grpc.example.com",
  port: 9090,
  protocol: :grpc
})

# Manual health check trigger
NsaiRegistry.HealthChecker.check_now()
NsaiRegistry.HealthChecker.check_service("work:localhost:4000")
```

### Event Subscriptions

```elixir
# Subscribe to all service events
NsaiRegistry.PubSub.subscribe()

# Subscribe to specific service events
NsaiRegistry.PubSub.subscribe("work")

# Use the Client helper for callbacks
NsaiRegistry.Client.watch("work",
  on_healthy: fn service ->
    Logger.info("Service #{service.name} is healthy!")
  end,
  on_unhealthy: fn service ->
    Logger.warning("Service #{service.name} is unhealthy!")
  end
)
```

### Circuit Breaker

```elixir
# The circuit breaker automatically protects health checks
# You can also use it directly:

NsaiRegistry.CircuitBreaker.call("my-operation", fn ->
  # Expensive or failure-prone operation
  perform_external_api_call()
end)

# Check circuit state
state = NsaiRegistry.CircuitBreaker.get_state("my-operation")
# Returns: :closed | :open | :half_open

# Get statistics
stats = NsaiRegistry.CircuitBreaker.stats()
```

## CLI Management

```bash
# List all registered services
mix nsai_registry.list

# Register a service
mix nsai_registry.register work localhost 4000 --health-check /health

# Register with metadata
mix nsai_registry.register api api.example.com 443 \
  --protocol https \
  --metadata version=1.0.0 \
  --metadata region=us-east

# Deregister a service
mix nsai_registry.deregister work:localhost:4000

# Trigger health checks
mix nsai_registry.health_check                      # All services
mix nsai_registry.health_check work:localhost:4000  # Specific service
```

## Telemetry Events

NsaiRegistry emits comprehensive telemetry events for monitoring:

```elixir
:telemetry.attach_many(
  "nsai-registry-handler",
  [
    [:nsai_registry, :register, :stop],
    [:nsai_registry, :deregister, :stop],
    [:nsai_registry, :lookup, :stop],
    [:nsai_registry, :health_check, :stop],
    [:nsai_registry, :status_change]
  ],
  fn event_name, measurements, metadata, _config ->
    # Log or send to monitoring system
    Logger.info("Event: #{inspect(event_name)}")
    Logger.info("Duration: #{measurements[:duration]}")
    Logger.info("Service: #{metadata[:service_name]}")
  end,
  nil
)
```

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run property-based tests
mix test test/nsai_registry/property_test.exs

# Run quality checks
mix format --check-formatted
mix credo --strict
mix dialyzer
```

## Development

```bash
# Get dependencies
mix deps.get

# Compile
mix compile

# Format code
mix format

# Run linter
mix credo --strict

# Type checking
mix dialyzer

# Generate documentation
mix docs

# Start IEx with the application
iex -S mix
```

## Production Deployment

### Recommended Configuration

```elixir
# config/prod.exs

config :nsai_registry, NsaiRegistry.Registry,
  storage_backend: NsaiRegistry.Storage.Postgres,
  storage_opts: [repo: MyApp.Repo]

config :nsai_registry, NsaiRegistry.HealthChecker,
  check_interval: 15_000,           # More frequent checks
  timeout: 3_000,
  auto_deregister: true,            # Auto-remove unhealthy services
  unhealthy_threshold: 2

config :nsai_registry, NsaiRegistry.CircuitBreaker,
  failure_threshold: 3,
  timeout: 30_000,
  half_open_max_calls: 2

# Enable telemetry reporting
config :nsai_registry, :telemetry,
  enabled: true,
  reporters: [MyApp.TelemetryReporter]
```

### Distributed Clustering (Optional)

For multi-node deployments with Horde:

```elixir
# config/config.exs
config :nsai_registry, :distributed, true

# In your application supervision tree
def start(_type, _args) do
  children = [
    # ... other children
    {Horde.Registry, [name: NsaiRegistry.HordeRegistry, keys: :unique]},
    {Horde.DynamicSupervisor, [name: NsaiRegistry.HordeSupervisor, strategy: :one_for_one]},
    NsaiRegistry.Application
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Performance Characteristics

### ETS Backend
- **Reads**: O(1) - Hash table lookups
- **Writes**: O(1) - Direct insertion
- **Memory**: In-memory only, lost on restart
- **Throughput**: Millions of ops/second
- **Best for**: Development, single-node deployments

### PostgreSQL Backend
- **Reads**: O(log n) with indexes
- **Writes**: O(log n) with B-tree
- **Memory**: Persistent storage
- **Throughput**: Thousands of ops/second
- **Best for**: Production, multi-node clusters

## Comparison with Alternatives

| Feature | NsaiRegistry | Consul | etcd | Eureka |
|---------|--------------|--------|------|--------|
| Language | Elixir | Go | Go | Java |
| Storage | ETS/Postgres | Raft | Raft | In-Memory |
| Health Checks | HTTP/TCP/gRPC | ✓ | ✗ | HTTP |
| Circuit Breaker | ✓ | ✗ | ✗ | ✗ |
| PubSub Events | ✓ | ✓ | ✓ | ✗ |
| Multi-Protocol | ✓ | Limited | Limited | HTTP Only |
| Elixir Native | ✓ | ✗ | ✗ | ✗ |

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `mix test`
5. Run quality checks: `mix format && mix credo --strict`
6. Submit a pull request

## License

Copyright (c) 2025 North Shore AI

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built on Phoenix PubSub for reliable event broadcasting
- Inspired by Consul, etcd, and Eureka
- Part of the North Shore AI ecosystem for ML reliability research

## Support

- Documentation: https://hexdocs.pm/nsai_registry
- Issues: https://github.com/North-Shore-AI/nsai_registry/issues
- Discussions: https://github.com/North-Shore-AI/nsai_registry/discussions
