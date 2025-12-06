# NsaiRegistry

Service discovery and registry for the NSAI (North Shore AI) ecosystem.

NsaiRegistry provides a lightweight, pluggable service registry with health checking, event broadcasting, and telemetry integration. Services can register themselves, discover other services, and receive notifications about topology changes.

## Features

- **Service Registration & Discovery** - Register and lookup services by name
- **Automatic Health Checking** - Periodic health checks with configurable intervals
- **Event Broadcasting** - PubSub notifications for topology changes
- **Telemetry Integration** - Built-in instrumentation for observability
- **Pluggable Storage** - ETS (in-memory) or Postgres (persistent) backends
- **Load Balancing Support** - Query all instances of a service for round-robin/weighted routing

## Installation

Add `nsai_registry` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nsai_registry, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Register a Service

```elixir
{:ok, service} = NsaiRegistry.register(%{
  name: "work",
  host: "localhost",
  port: 4000,
  protocol: :http,
  health_check: "/health",
  metadata: %{version: "0.1.0", env: "prod"}
})

# Service registered and health checks will start automatically
```

### 2. Discover Services

```elixir
# Lookup first instance
{:ok, service} = NsaiRegistry.lookup("work")
#=> %NsaiRegistry.Service{
#     name: "work",
#     host: "localhost",
#     port: 4000,
#     protocol: :http,
#     status: :healthy
#   }

# Lookup all instances (for load balancing)
{:ok, services} = NsaiRegistry.lookup_all("work")
#=> [%NsaiRegistry.Service{}, %NsaiRegistry.Service{}, ...]
```

### 3. Subscribe to Events

```elixir
# Subscribe to all service events
NsaiRegistry.PubSub.subscribe()

# Or subscribe to specific service
NsaiRegistry.PubSub.subscribe("work")

# Handle events
receive do
  {:service_registered, service} ->
    IO.puts("New service: #{service.name}")

  {:service_healthy, service} ->
    IO.puts("Service #{service.name} is healthy")

  {:service_unhealthy, service} ->
    IO.puts("Service #{service.name} is unhealthy")

  {:service_deregistered, service_id} ->
    IO.puts("Service #{service_id} removed")
end
```

## Configuration

Configure in `config/config.exs`:

```elixir
# Storage backend (default: ETS)
config :nsai_registry, NsaiRegistry.Registry,
  storage_backend: NsaiRegistry.Storage.ETS,
  storage_opts: [table_name: :nsai_registry]

# For persistent storage, use Postgres
config :nsai_registry, NsaiRegistry.Registry,
  storage_backend: NsaiRegistry.Storage.Postgres,
  storage_opts: [repo: MyApp.Repo]

# Health checker configuration
config :nsai_registry, NsaiRegistry.HealthChecker,
  check_interval: 30_000,        # Check every 30 seconds
  timeout: 5_000,                # 5 second timeout per check
  auto_deregister: false,        # Don't auto-remove unhealthy services
  unhealthy_threshold: 3         # Deregister after 3 consecutive failures
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     NsaiRegistry.Application                 │
│                                                              │
│  ┌────────────────┐  ┌──────────────────┐  ┌──────────────┐│
│  │   PubSub       │  │   Registry       │  │ HealthChecker││
│  │                │  │   GenServer      │  │   GenServer  ││
│  │ (Phoenix.PubSub)│  │                 │  │              ││
│  └────────────────┘  └──────────────────┘  └──────────────┘│
│                             │                      │         │
│                             ▼                      │         │
│                      ┌─────────────┐              │         │
│                      │   Storage   │              │         │
│                      │  (ETS/PG)   │◄─────────────┘         │
│                      └─────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **NsaiRegistry.Service** - Service struct with metadata
2. **NsaiRegistry.Registry** - Core GenServer for registration/lookup
3. **NsaiRegistry.Storage.ETS** - In-memory storage backend
4. **NsaiRegistry.Storage.Postgres** - Persistent storage backend (optional)
5. **NsaiRegistry.HealthChecker** - Background health check worker
6. **NsaiRegistry.PubSub** - Event broadcasting via Phoenix.PubSub
7. **NsaiRegistry.Telemetry** - Instrumentation for observability

## API Reference

### Registration

```elixir
# Register a service
{:ok, service} = NsaiRegistry.register(%{
  name: "work",           # required
  host: "localhost",      # required
  port: 4000,            # required
  protocol: :http,       # optional, default: :http
  health_check: "/health", # optional
  metadata: %{}          # optional
})

# Deregister a service
:ok = NsaiRegistry.deregister("work:localhost:4000")
```

### Discovery

```elixir
# Lookup by name (returns first match)
{:ok, service | nil} = NsaiRegistry.lookup("work")

# Lookup by ID
{:ok, service} = NsaiRegistry.lookup_by_id("work:localhost:4000")

# Lookup all instances
{:ok, [service]} = NsaiRegistry.lookup_all("work")

# List all services
{:ok, [service]} = NsaiRegistry.list_all()
```

### Status Management

```elixir
# Update service status manually
:ok = NsaiRegistry.update_status("work:localhost:4000", :healthy)

# Status is automatically updated by HealthChecker
```

## Events

Subscribe to service topology changes:

| Event | Description |
|-------|-------------|
| `{:service_registered, service}` | New service registered |
| `{:service_deregistered, service_id}` | Service removed |
| `{:service_status_changed, service_id, old, new}` | Status updated |
| `{:service_healthy, service}` | Service became healthy |
| `{:service_unhealthy, service}` | Service became unhealthy |

## Telemetry

Instrumentation events for monitoring:

```elixir
:telemetry.attach(
  "my-handler",
  [:nsai_registry, :register, :stop],
  fn _event, measurements, metadata, _config ->
    # Log or emit metrics
    Logger.info("Service registered",
      service: metadata.service_name,
      duration: measurements.duration
    )
  end,
  nil
)
```

Available events:
- `[:nsai_registry, :register, :start|:stop|:exception]`
- `[:nsai_registry, :deregister, :start|:stop]`
- `[:nsai_registry, :lookup, :start|:stop]`
- `[:nsai_registry, :health_check, :start|:stop|:exception]`
- `[:nsai_registry, :status_change]`

## Use Cases

### Service Discovery for NSAI Microservices

```elixir
# Work service registers itself on startup
defmodule Work.Application do
  def start(_type, _args) do
    # ... start supervision tree

    NsaiRegistry.register(%{
      name: "work",
      host: Application.get_env(:work, :host),
      port: Application.get_env(:work, :port),
      health_check: "/health"
    })

    # ...
  end
end

# Gateway discovers Work service
defmodule Gateway.Router do
  def forward_to_work(conn) do
    {:ok, service} = NsaiRegistry.lookup("work")
    url = NsaiRegistry.Service.url(service)

    # Forward request to work service
    proxy(conn, url)
  end
end
```

### Load Balancing

```elixir
defmodule LoadBalancer do
  def round_robin(service_name) do
    {:ok, services} = NsaiRegistry.lookup_all(service_name)

    # Filter to healthy services only
    healthy = Enum.filter(services, &(&1.status == :healthy))

    # Pick next service (round-robin logic)
    index = :persistent_term.get({__MODULE__, service_name}, 0)
    service = Enum.at(healthy, rem(index, length(healthy)))

    :persistent_term.put({__MODULE__, service_name}, index + 1)

    service
  end
end
```

### Auto-Deregistration of Unhealthy Services

```elixir
# In config/config.exs
config :nsai_registry, NsaiRegistry.HealthChecker,
  check_interval: 10_000,
  auto_deregister: true,
  unhealthy_threshold: 5  # Remove after 5 failed checks
```

## Testing

Run the test suite:

```bash
mix test
```

Run with coverage:

```bash
mix test --cover
```

## Development

```bash
# Clone the repository
git clone https://github.com/North-Shore-AI/nsai_registry.git
cd nsai_registry

# Install dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Format code
mix format

# Type checking (if dialyzer configured)
mix dialyzer
```

## Roadmap

- [ ] Add support for DNS-based service discovery
- [ ] Implement distributed registry with Horde
- [ ] Add service versioning and blue/green deployments
- [ ] Web UI for service topology visualization
- [ ] Consul/etcd integration
- [ ] Circuit breaker integration
- [ ] Service mesh capabilities

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

Apache 2.0

## Related Projects

- [Work](https://github.com/North-Shore-AI/work) - Job scheduler for NSAI
- [Forge](https://github.com/North-Shore-AI/forge) - Sample factory for ML pipelines
- [Anvil](https://github.com/North-Shore-AI/anvil) - Labeling queue management
- [Ingot](https://github.com/North-Shore-AI/ingot) - Labeling UI
