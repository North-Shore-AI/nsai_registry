defmodule NsaiRegistry.Telemetry do
  @moduledoc """
  Telemetry instrumentation for service registry operations.

  Emits telemetry events for registration, lookups, health checks, and status changes.

  ## Events

  - `[:nsai_registry, :register, :start]` - Service registration started
  - `[:nsai_registry, :register, :stop]` - Service registration completed
  - `[:nsai_registry, :register, :exception]` - Service registration failed
  - `[:nsai_registry, :deregister, :start]` - Service deregistration started
  - `[:nsai_registry, :deregister, :stop]` - Service deregistration completed
  - `[:nsai_registry, :lookup, :start]` - Service lookup started
  - `[:nsai_registry, :lookup, :stop]` - Service lookup completed
  - `[:nsai_registry, :health_check, :start]` - Health check started
  - `[:nsai_registry, :health_check, :stop]` - Health check completed
  - `[:nsai_registry, :health_check, :exception]` - Health check failed
  - `[:nsai_registry, :status_change]` - Service status changed

  ## Measurements

  All `:start`/`:stop` events include:
  - `duration` - Operation duration in native time units

  ## Metadata

  Events include relevant metadata:
  - `service_name` - Name of the service
  - `service_id` - Unique service identifier
  - `status` - Service status
  - `old_status` - Previous status (for status_change events)

  ## Examples

      # Attach a handler
      :telemetry.attach(
        "my-handler",
        [:nsai_registry, :register, :stop],
        fn _event, measurements, metadata, _config ->
          IO.puts("Registered service in duration: " <> to_string(measurements.duration))
          IO.inspect(metadata)
        end,
        nil
      )
  """

  @doc """
  Emits telemetry for service registration.
  """
  def register(fun, metadata \\ %{}) do
    execute(:register, fun, metadata)
  end

  @doc """
  Emits telemetry for service deregistration.
  """
  def deregister(fun, metadata \\ %{}) do
    execute(:deregister, fun, metadata)
  end

  @doc """
  Emits telemetry for service lookup.
  """
  def lookup(fun, metadata \\ %{}) do
    execute(:lookup, fun, metadata)
  end

  @doc """
  Emits telemetry for health check.
  """
  def health_check(fun, metadata \\ %{}) do
    execute(:health_check, fun, metadata)
  end

  @doc """
  Emits telemetry for status change.
  """
  def status_change(metadata) do
    :telemetry.execute(
      [:nsai_registry, :status_change],
      %{timestamp: System.monotonic_time()},
      metadata
    )
  end

  # Private functions

  defp execute(event_name, fun, metadata) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:nsai_registry, event_name, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        [:nsai_registry, event_name, :stop],
        %{duration: System.monotonic_time() - start_time},
        metadata
      )

      result
    rescue
      exception ->
        :telemetry.execute(
          [:nsai_registry, event_name, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{exception: exception, stacktrace: __STACKTRACE__})
        )

        reraise exception, __STACKTRACE__
    end
  end
end
