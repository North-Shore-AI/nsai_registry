defmodule NsaiRegistry.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias NsaiRegistry.Service

  setup do
    # Application is already started by the test helper
    # Just ensure clean state by deregistering all services
    case NsaiRegistry.list_all() do
      {:ok, services} ->
        Enum.each(services, fn service ->
          NsaiRegistry.deregister(NsaiRegistry.Service.id(service))
        end)

      _ ->
        :ok
    end

    :ok
  end

  describe "Service.new/1 properties" do
    property "always generates a valid service with required fields" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              port <- integer(1..65535),
              protocol <- member_of([:http, :https, :tcp, :grpc])
            ) do
        attrs = %{
          name: name,
          host: host,
          port: port,
          protocol: protocol
        }

        assert {:ok, service} = Service.new(attrs)
        assert service.name == name
        assert service.host == host
        assert service.port == port
        assert service.protocol == protocol
        assert service.status == :unknown
        assert %DateTime{} = service.registered_at
      end
    end

    property "service ID is deterministic and unique for different services" do
      check all(
              name1 <- string(:alphanumeric, min_length: 1, max_length: 50),
              name2 <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              port1 <- integer(1..65535),
              port2 <- integer(1..65535)
            ) do
        {:ok, service1} = Service.new(%{name: name1, host: host, port: port1})
        {:ok, service2} = Service.new(%{name: name2, host: host, port: port2})

        id1 = Service.id(service1)
        id2 = Service.id(service2)

        # Same service generates same ID
        {:ok, service1_dup} = Service.new(%{name: name1, host: host, port: port1})
        assert Service.id(service1_dup) == id1

        # Different services generate different IDs (if actually different)
        if name1 != name2 or port1 != port2 do
          assert id1 != id2
        end
      end
    end

    property "URL format is always valid" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              port <- integer(1..65535),
              protocol <- member_of([:http, :https, :tcp, :grpc])
            ) do
        {:ok, service} = Service.new(%{name: name, host: host, port: port, protocol: protocol})
        url = Service.url(service)

        assert String.starts_with?(url, "#{protocol}://")
        assert String.contains?(url, host)
        assert String.contains?(url, ":#{port}")
      end
    end
  end

  describe "Registry operations properties" do
    property "registering and looking up a service is idempotent" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              port <- integer(1..65535)
            ) do
        attrs = %{name: name, host: host, port: port}

        # Register twice
        assert {:ok, service1} = NsaiRegistry.register(attrs)
        assert {:ok, service2} = NsaiRegistry.register(attrs)

        # Should have same ID
        assert Service.id(service1) == Service.id(service2)

        # Lookup should return the service
        assert {:ok, found} = NsaiRegistry.lookup(name)
        assert found.name == name
        assert found.host == host
        assert found.port == port

        # Cleanup
        NsaiRegistry.deregister(Service.id(service1))
      end
    end

    property "deregistering makes a service unfindable" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              port <- integer(1..65535)
            ) do
        attrs = %{name: name, host: host, port: port}

        {:ok, service} = NsaiRegistry.register(attrs)
        service_id = Service.id(service)

        # Should be findable
        assert {:ok, %Service{}} = NsaiRegistry.lookup(name)

        # Deregister
        assert :ok = NsaiRegistry.deregister(service_id)

        # Should not be findable
        assert {:ok, nil} = NsaiRegistry.lookup(name)
      end
    end

    property "lookup_all returns all instances of a service" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              ports <- uniq_list_of(integer(1..65535), min_length: 1, max_length: 5)
            ) do
        # Register multiple instances
        services =
          Enum.map(ports, fn port ->
            {:ok, service} = NsaiRegistry.register(%{name: name, host: host, port: port})
            service
          end)

        # Lookup all should return all instances
        assert {:ok, found_services} = NsaiRegistry.lookup_all(name)
        assert length(found_services) == length(services)

        # Cleanup
        Enum.each(services, fn service ->
          NsaiRegistry.deregister(Service.id(service))
        end)
      end
    end

    property "status updates are reflected in lookups" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              port <- integer(1..65535),
              new_status <- member_of([:healthy, :unhealthy, :unknown])
            ) do
        attrs = %{name: name, host: host, port: port}
        {:ok, service} = NsaiRegistry.register(attrs)
        service_id = Service.id(service)

        # Update status
        assert :ok = NsaiRegistry.update_status(service_id, new_status)

        # Lookup should reflect new status
        assert {:ok, updated} = NsaiRegistry.lookup(name)
        assert updated.status == new_status

        # Cleanup
        NsaiRegistry.deregister(service_id)
      end
    end
  end

  describe "Client load balancing properties" do
    property "round_robin cycles through all healthy instances" do
      check all(
              name <- string(:alphanumeric, min_length: 1, max_length: 50),
              host <- string(:alphanumeric, min_length: 1, max_length: 100),
              ports <- uniq_list_of(integer(1..65535), min_length: 2, max_length: 5)
            ) do
        # Register instances
        services =
          Enum.map(ports, fn port ->
            {:ok, service} = NsaiRegistry.register(%{name: name, host: host, port: port})
            service
          end)

        # Mark all healthy
        Enum.each(services, fn service ->
          NsaiRegistry.update_status(Service.id(service), :healthy)
        end)

        # Round robin should cycle through all instances
        selected =
          for _ <- 1..(length(services) * 2) do
            {:ok, service} = NsaiRegistry.Client.round_robin(name)
            service.port
          end

        # Each instance should be selected at least once
        ports_set = MapSet.new(ports)
        selected_set = MapSet.new(selected)
        assert MapSet.subset?(ports_set, selected_set)

        # Cleanup
        Enum.each(services, fn service ->
          NsaiRegistry.deregister(Service.id(service))
        end)
      end
    end
  end
end
