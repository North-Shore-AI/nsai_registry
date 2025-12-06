defmodule NsaiRegistry.PubSub do
  @moduledoc """
  Event broadcasting for service registry changes.

  Publishes events when services are registered, deregistered, or change status.
  Applications can subscribe to these events to react to service topology changes.

  ## Events

  - `{:service_registered, service}` - New service registered
  - `{:service_deregistered, service_id}` - Service removed
  - `{:service_status_changed, service_id, old_status, new_status}` - Status updated
  - `{:service_healthy, service}` - Service became healthy
  - `{:service_unhealthy, service}` - Service became unhealthy

  ## Examples

      # Subscribe to all events
      NsaiRegistry.PubSub.subscribe()

      # Subscribe to specific service
      NsaiRegistry.PubSub.subscribe("work")

      # Handle events
      receive do
        {:service_registered, svc} ->
          IO.puts("New service: " <> svc.name)
      end
  """

  alias NsaiRegistry.Service

  @pubsub_name NsaiRegistry.PubSub
  @topic "service_registry"

  @doc """
  Starts the PubSub system.
  """
  def child_spec(_opts) do
    Phoenix.PubSub.child_spec(name: @pubsub_name)
  end

  @doc """
  Subscribes to all service registry events.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub_name, @topic)
  end

  @doc """
  Subscribes to events for a specific service name.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(service_name) do
    Phoenix.PubSub.subscribe(@pubsub_name, service_topic(service_name))
  end

  @doc """
  Unsubscribes from all service registry events.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(@pubsub_name, @topic)
  end

  @doc """
  Unsubscribes from events for a specific service name.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(service_name) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, service_topic(service_name))
  end

  @doc """
  Broadcasts that a service was registered.
  """
  @spec broadcast_registered(Service.t()) :: :ok
  def broadcast_registered(%Service{} = service) do
    broadcast({:service_registered, service}, service.name)
  end

  @doc """
  Broadcasts that a service was deregistered.
  """
  @spec broadcast_deregistered(String.t(), String.t()) :: :ok
  def broadcast_deregistered(service_id, service_name) do
    broadcast({:service_deregistered, service_id}, service_name)
  end

  @doc """
  Broadcasts that a service status changed.
  """
  @spec broadcast_status_changed(Service.t(), Service.status()) :: :ok
  def broadcast_status_changed(%Service{} = service, old_status) do
    message = {:service_status_changed, Service.id(service), old_status, service.status}
    broadcast(message, service.name)

    # Also send specific health events
    case service.status do
      :healthy -> broadcast({:service_healthy, service}, service.name)
      :unhealthy -> broadcast({:service_unhealthy, service}, service.name)
      _ -> :ok
    end
  end

  # Private functions

  defp broadcast(message, service_name) do
    # Broadcast to general topic
    Phoenix.PubSub.broadcast(@pubsub_name, @topic, message)

    # Broadcast to service-specific topic
    Phoenix.PubSub.broadcast(@pubsub_name, service_topic(service_name), message)
  end

  defp service_topic(service_name) do
    "#{@topic}:#{service_name}"
  end
end
