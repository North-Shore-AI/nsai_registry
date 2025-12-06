defmodule NsaiRegistry.PubSubTest do
  use ExUnit.Case, async: false

  alias NsaiRegistry.{PubSub, Service}

  setup do
    # Ensure clean state
    :ok = Application.stop(:nsai_registry)
    :ok = Application.start(:nsai_registry)

    # Unsubscribe in case of previous test failures
    PubSub.unsubscribe()

    :ok
  end

  describe "subscribe/0 and unsubscribe/0" do
    test "subscribes to all service events" do
      assert :ok = PubSub.subscribe()

      {:ok, service} =
        Service.new(%{name: "work", host: "localhost", port: 4000})

      PubSub.broadcast_registered(service)

      assert_receive {:service_registered, ^service}, 500
    end

    test "unsubscribes from all events" do
      PubSub.subscribe()
      assert :ok = PubSub.unsubscribe()

      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      PubSub.broadcast_registered(service)

      refute_receive {:service_registered, _}, 100
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribes to specific service events" do
      assert :ok = PubSub.subscribe("work")

      {:ok, work_service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      {:ok, forge_service} = Service.new(%{name: "forge", host: "localhost", port: 5000})

      PubSub.broadcast_registered(work_service)
      PubSub.broadcast_registered(forge_service)

      # Should receive work event
      assert_receive {:service_registered, %{name: "work"}}, 500

      # Should not receive forge event
      refute_receive {:service_registered, %{name: "forge"}}, 100
    end

    test "unsubscribes from specific service events" do
      PubSub.subscribe("work")
      assert :ok = PubSub.unsubscribe("work")

      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      PubSub.broadcast_registered(service)

      refute_receive {:service_registered, _}, 100
    end
  end

  describe "broadcast_registered/1" do
    test "broadcasts service registered event" do
      PubSub.subscribe()

      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      assert :ok = PubSub.broadcast_registered(service)

      assert_receive {:service_registered, received_service}, 500
      assert received_service.name == "work"
    end
  end

  describe "broadcast_deregistered/2" do
    test "broadcasts service deregistered event" do
      PubSub.subscribe()

      service_id = "work:localhost:4000"
      assert :ok = PubSub.broadcast_deregistered(service_id, "work")

      assert_receive {:service_deregistered, ^service_id}, 500
    end
  end

  describe "broadcast_status_changed/2" do
    test "broadcasts status change event" do
      PubSub.subscribe()

      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      updated = Service.update_status(service, :healthy)

      assert :ok = PubSub.broadcast_status_changed(updated, :unknown)

      service_id = Service.id(service)

      assert_receive {:service_status_changed, ^service_id, :unknown, :healthy}, 500
    end

    test "broadcasts service_healthy event when status becomes healthy" do
      PubSub.subscribe()

      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      updated = Service.update_status(service, :healthy)

      PubSub.broadcast_status_changed(updated, :unknown)

      assert_receive {:service_healthy, ^updated}, 500
    end

    test "broadcasts service_unhealthy event when status becomes unhealthy" do
      PubSub.subscribe()

      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      updated = Service.update_status(service, :unhealthy)

      PubSub.broadcast_status_changed(updated, :healthy)

      assert_receive {:service_unhealthy, ^updated}, 500
    end
  end
end
