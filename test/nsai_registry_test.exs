defmodule NsaiRegistryTest do
  use ExUnit.Case, async: false

  alias NsaiRegistry.Service

  setup do
    # Ensure clean state for each test
    :ok = Application.stop(:nsai_registry)
    :ok = Application.start(:nsai_registry)

    on_exit(fn ->
      # Clean up registered services
      case NsaiRegistry.list_all() do
        {:ok, services} ->
          Enum.each(services, fn service ->
            NsaiRegistry.deregister(Service.id(service))
          end)

        _ ->
          :ok
      end
    end)

    :ok
  end

  describe "register/1" do
    test "registers a service successfully" do
      attrs = %{
        name: "work",
        host: "localhost",
        port: 4000,
        protocol: :http,
        health_check: "/health",
        metadata: %{version: "0.1.0"}
      }

      assert {:ok, %Service{} = service} = NsaiRegistry.register(attrs)
      assert service.name == "work"
      assert service.host == "localhost"
      assert service.port == 4000
      assert service.protocol == :http
      assert service.health_check == "/health"
      assert service.metadata == %{version: "0.1.0"}
      assert service.status == :unknown
    end

    test "requires name, host, and port" do
      assert {:error, :missing_required_fields} = NsaiRegistry.register(%{name: "work"})
      assert {:error, :missing_required_fields} = NsaiRegistry.register(%{host: "localhost"})
      assert {:error, :missing_required_fields} = NsaiRegistry.register(%{port: 4000})
    end

    test "validates protocol" do
      attrs = %{name: "work", host: "localhost", port: 4000, protocol: :invalid}
      assert {:error, :invalid_protocol} = NsaiRegistry.register(attrs)
    end

    test "uses default protocol if not specified" do
      attrs = %{name: "work", host: "localhost", port: 4000}
      assert {:ok, %Service{protocol: :http}} = NsaiRegistry.register(attrs)
    end
  end

  describe "lookup/1" do
    test "finds registered service by name" do
      attrs = %{name: "work", host: "localhost", port: 4000}
      {:ok, registered} = NsaiRegistry.register(attrs)

      assert {:ok, %Service{} = found} = NsaiRegistry.lookup("work")
      assert found.name == registered.name
      assert found.host == registered.host
      assert found.port == registered.port
    end

    test "returns nil for non-existent service" do
      assert {:ok, nil} = NsaiRegistry.lookup("nonexistent")
    end

    test "returns a service when multiple instances exist" do
      {:ok, _} = NsaiRegistry.register(%{name: "work", host: "localhost", port: 4000})
      {:ok, _} = NsaiRegistry.register(%{name: "work", host: "localhost", port: 4001})

      # Just verify we get a service, don't rely on ordering
      assert {:ok, %Service{name: "work"} = service} = NsaiRegistry.lookup("work")
      assert service.port in [4000, 4001]
    end
  end

  describe "lookup_all/1" do
    test "finds all instances of a service" do
      {:ok, _} = NsaiRegistry.register(%{name: "work", host: "localhost", port: 4000})
      {:ok, _} = NsaiRegistry.register(%{name: "work", host: "localhost", port: 4001})
      {:ok, _} = NsaiRegistry.register(%{name: "forge", host: "localhost", port: 5000})

      assert {:ok, services} = NsaiRegistry.lookup_all("work")
      assert length(services) == 2
      assert Enum.all?(services, fn s -> s.name == "work" end)
    end

    test "returns empty list for non-existent service" do
      assert {:ok, []} = NsaiRegistry.lookup_all("nonexistent")
    end
  end

  describe "lookup_by_id/1" do
    test "finds service by ID" do
      attrs = %{name: "work", host: "localhost", port: 4000}
      {:ok, registered} = NsaiRegistry.register(attrs)
      service_id = Service.id(registered)

      assert {:ok, %Service{} = found} = NsaiRegistry.lookup_by_id(service_id)
      assert found.name == registered.name
    end

    test "returns error for non-existent ID" do
      assert {:error, :not_found} = NsaiRegistry.lookup_by_id("nonexistent:id:0")
    end
  end

  describe "list_all/0" do
    test "lists all registered services" do
      {:ok, _} = NsaiRegistry.register(%{name: "work", host: "localhost", port: 4000})
      {:ok, _} = NsaiRegistry.register(%{name: "forge", host: "localhost", port: 5000})

      assert {:ok, services} = NsaiRegistry.list_all()
      assert length(services) == 2
      assert Enum.map(services, & &1.name) |> Enum.sort() == ["forge", "work"]
    end

    test "returns empty list when no services registered" do
      assert {:ok, []} = NsaiRegistry.list_all()
    end
  end

  describe "deregister/1" do
    test "removes a registered service" do
      attrs = %{name: "work", host: "localhost", port: 4000}
      {:ok, service} = NsaiRegistry.register(attrs)
      service_id = Service.id(service)

      assert :ok = NsaiRegistry.deregister(service_id)
      assert {:ok, nil} = NsaiRegistry.lookup("work")
    end

    test "deregistering non-existent service returns ok" do
      assert :ok = NsaiRegistry.deregister("nonexistent:id:0")
    end
  end

  describe "update_status/2" do
    test "updates service status" do
      attrs = %{name: "work", host: "localhost", port: 4000}
      {:ok, service} = NsaiRegistry.register(attrs)
      service_id = Service.id(service)

      assert :ok = NsaiRegistry.update_status(service_id, :healthy)

      {:ok, updated} = NsaiRegistry.lookup_by_id(service_id)
      assert updated.status == :healthy
      assert updated.last_check != nil
    end

    test "handles multiple status changes" do
      attrs = %{name: "work", host: "localhost", port: 4000}
      {:ok, service} = NsaiRegistry.register(attrs)
      service_id = Service.id(service)

      assert :ok = NsaiRegistry.update_status(service_id, :healthy)
      assert :ok = NsaiRegistry.update_status(service_id, :unhealthy)
      assert :ok = NsaiRegistry.update_status(service_id, :healthy)

      {:ok, updated} = NsaiRegistry.lookup_by_id(service_id)
      assert updated.status == :healthy
    end
  end
end
