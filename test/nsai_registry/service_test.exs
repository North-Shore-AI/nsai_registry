defmodule NsaiRegistry.ServiceTest do
  use ExUnit.Case, async: true

  alias NsaiRegistry.Service

  describe "new/1" do
    test "creates a service with required fields" do
      attrs = %{
        name: "work",
        host: "localhost",
        port: 4000
      }

      assert {:ok, %Service{} = service} = Service.new(attrs)
      assert service.name == "work"
      assert service.host == "localhost"
      assert service.port == 4000
      assert service.protocol == :http
      assert service.status == :unknown
      assert service.metadata == %{}
      assert service.registered_at != nil
      assert service.last_check == nil
    end

    test "creates a service with optional fields" do
      attrs = %{
        name: "work",
        host: "localhost",
        port: 4000,
        protocol: :https,
        health_check: "/health",
        metadata: %{version: "1.0.0", env: "prod"}
      }

      assert {:ok, %Service{} = service} = Service.new(attrs)
      assert service.protocol == :https
      assert service.health_check == "/health"
      assert service.metadata == %{version: "1.0.0", env: "prod"}
    end

    test "requires name field" do
      attrs = %{host: "localhost", port: 4000}
      assert {:error, :missing_required_fields} = Service.new(attrs)
    end

    test "requires host field" do
      attrs = %{name: "work", port: 4000}
      assert {:error, :missing_required_fields} = Service.new(attrs)
    end

    test "requires port field" do
      attrs = %{name: "work", host: "localhost"}
      assert {:error, :missing_required_fields} = Service.new(attrs)
    end

    test "validates protocol" do
      attrs = %{name: "work", host: "localhost", port: 4000, protocol: :invalid}
      assert {:error, :invalid_protocol} = Service.new(attrs)
    end

    test "accepts valid protocols" do
      attrs = %{name: "work", host: "localhost", port: 4000}

      for protocol <- [:http, :https, :tcp, :grpc] do
        assert {:ok, %Service{protocol: ^protocol}} =
                 Service.new(Map.put(attrs, :protocol, protocol))
      end
    end
  end

  describe "id/1" do
    test "generates unique ID from name, host, and port" do
      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      assert Service.id(service) == "work:localhost:4000"
    end

    test "generates different IDs for different services" do
      {:ok, service1} = Service.new(%{name: "work", host: "localhost", port: 4000})
      {:ok, service2} = Service.new(%{name: "work", host: "localhost", port: 4001})

      assert Service.id(service1) != Service.id(service2)
    end

    test "generates same ID for identical services" do
      {:ok, service1} = Service.new(%{name: "work", host: "localhost", port: 4000})
      {:ok, service2} = Service.new(%{name: "work", host: "localhost", port: 4000})

      assert Service.id(service1) == Service.id(service2)
    end
  end

  describe "url/1" do
    test "generates URL for HTTP service" do
      {:ok, service} =
        Service.new(%{name: "work", host: "localhost", port: 4000, protocol: :http})

      assert Service.url(service) == "http://localhost:4000"
    end

    test "generates URL for HTTPS service" do
      {:ok, service} =
        Service.new(%{name: "work", host: "example.com", port: 443, protocol: :https})

      assert Service.url(service) == "https://example.com:443"
    end

    test "generates URL for TCP service" do
      {:ok, service} =
        Service.new(%{name: "work", host: "192.168.1.1", port: 8080, protocol: :tcp})

      assert Service.url(service) == "tcp://192.168.1.1:8080"
    end
  end

  describe "health_check_url/1" do
    test "returns full health check URL when configured" do
      {:ok, service} =
        Service.new(%{
          name: "work",
          host: "localhost",
          port: 4000,
          protocol: :http,
          health_check: "/health"
        })

      assert Service.health_check_url(service) == "http://localhost:4000/health"
    end

    test "returns nil when health check not configured" do
      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      assert Service.health_check_url(service) == nil
    end

    test "handles different protocols" do
      {:ok, service} =
        Service.new(%{
          name: "work",
          host: "example.com",
          port: 443,
          protocol: :https,
          health_check: "/api/health"
        })

      assert Service.health_check_url(service) == "https://example.com:443/api/health"
    end
  end

  describe "update_status/2" do
    test "updates status to healthy" do
      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      updated = Service.update_status(service, :healthy)

      assert updated.status == :healthy
      assert %DateTime{} = updated.last_check
    end

    test "updates status to unhealthy" do
      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      updated = Service.update_status(service, :unhealthy)

      assert updated.status == :unhealthy
      assert %DateTime{} = updated.last_check
    end

    test "updates status to unknown" do
      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      healthy = Service.update_status(service, :healthy)
      unknown = Service.update_status(healthy, :unknown)

      assert unknown.status == :unknown
      assert %DateTime{} = unknown.last_check
    end

    test "updates last_check timestamp on each status change" do
      {:ok, service} = Service.new(%{name: "work", host: "localhost", port: 4000})
      first = Service.update_status(service, :healthy)

      Process.sleep(10)

      second = Service.update_status(first, :unhealthy)

      assert DateTime.compare(second.last_check, first.last_check) == :gt
    end
  end
end
