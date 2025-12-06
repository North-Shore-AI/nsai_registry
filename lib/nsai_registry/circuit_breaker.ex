defmodule NsaiRegistry.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern for service health management.

  Prevents cascading failures by temporarily disabling health checks
  for services that are consistently failing.

  ## States

  - `:closed` - Normal operation, requests flow through
  - `:open` - Circuit is open, requests fail fast
  - `:half_open` - Testing if service has recovered

  ## Configuration

      config :nsai_registry, NsaiRegistry.CircuitBreaker,
        failure_threshold: 5,        # Failures before opening
        timeout: 60_000,             # Time before attempting reset (ms)
        half_open_max_calls: 3       # Max calls in half-open state

  ## Example

      case NsaiRegistry.CircuitBreaker.call(service_id, fn ->
        perform_health_check(service)
      end) do
        {:ok, result} -> result
        {:error, :circuit_open} -> :skip_check
        {:error, reason} -> handle_error(reason)
      end
  """

  use GenServer
  require Logger

  @type circuit_state :: :closed | :open | :half_open

  @type state :: %{
          circuits: %{
            String.t() => %{
              state: circuit_state(),
              failures: non_neg_integer(),
              last_failure: DateTime.t() | nil,
              half_open_calls: non_neg_integer()
            }
          },
          config: keyword()
        }

  # Configuration defaults
  @default_failure_threshold 5
  @default_timeout 60_000
  @default_half_open_max_calls 3

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a function within a circuit breaker context.

  If the circuit is open, returns `{:error, :circuit_open}` immediately.
  Otherwise, executes the function and updates circuit state based on result.
  """
  @spec call(String.t(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def call(circuit_id, fun) do
    GenServer.call(__MODULE__, {:call, circuit_id, fun})
  end

  @doc """
  Gets the current state of a circuit.
  """
  @spec get_state(String.t()) :: circuit_state()
  def get_state(circuit_id) do
    GenServer.call(__MODULE__, {:get_state, circuit_id})
  end

  @doc """
  Resets a circuit to closed state.
  """
  @spec reset(String.t()) :: :ok
  def reset(circuit_id) do
    GenServer.cast(__MODULE__, {:reset, circuit_id})
  end

  @doc """
  Gets statistics for all circuits.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    config = [
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      half_open_max_calls: Keyword.get(opts, :half_open_max_calls, @default_half_open_max_calls)
    ]

    state = %{
      circuits: %{},
      config: config
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:call, circuit_id, fun}, _from, state) do
    circuit = get_or_create_circuit(state.circuits, circuit_id)
    circuit = maybe_transition_to_half_open(circuit, state.config)

    case circuit.state do
      :open ->
        {:reply, {:error, :circuit_open}, state}

      :half_open ->
        if circuit.half_open_calls >= state.config[:half_open_max_calls] do
          {:reply, {:error, :circuit_open}, state}
        else
          execute_and_update(circuit_id, circuit, fun, state)
        end

      :closed ->
        execute_and_update(circuit_id, circuit, fun, state)
    end
  end

  @impl true
  def handle_call({:get_state, circuit_id}, _from, state) do
    circuit = get_or_create_circuit(state.circuits, circuit_id)
    {:reply, circuit.state, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats =
      Enum.map(state.circuits, fn {id, circuit} ->
        {id,
         %{
           state: circuit.state,
           failures: circuit.failures,
           last_failure: circuit.last_failure
         }}
      end)
      |> Enum.into(%{})

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:reset, circuit_id}, state) do
    circuit = %{
      state: :closed,
      failures: 0,
      last_failure: nil,
      half_open_calls: 0
    }

    circuits = Map.put(state.circuits, circuit_id, circuit)
    {:noreply, %{state | circuits: circuits}}
  end

  # Private functions

  defp get_or_create_circuit(circuits, circuit_id) do
    Map.get(circuits, circuit_id, %{
      state: :closed,
      failures: 0,
      last_failure: nil,
      half_open_calls: 0
    })
  end

  defp maybe_transition_to_half_open(circuit, config) do
    if circuit.state == :open and circuit.last_failure do
      elapsed = DateTime.diff(DateTime.utc_now(), circuit.last_failure, :millisecond)

      if elapsed >= config[:timeout] do
        Logger.info("Circuit transitioning to half-open for testing")

        %{circuit | state: :half_open, half_open_calls: 0}
      else
        circuit
      end
    else
      circuit
    end
  end

  defp execute_and_update(circuit_id, circuit, fun, state) do
    case fun.() do
      {:ok, result} ->
        # Success - reset or close circuit
        new_circuit = %{
          state: :closed,
          failures: 0,
          last_failure: nil,
          half_open_calls: 0
        }

        circuits = Map.put(state.circuits, circuit_id, new_circuit)
        {:reply, {:ok, result}, %{state | circuits: circuits}}

      {:error, _reason} = error ->
        # Failure - increment and possibly open circuit
        new_failures = circuit.failures + 1
        now = DateTime.utc_now()

        new_circuit =
          if new_failures >= state.config[:failure_threshold] do
            Logger.warning(
              "Circuit breaker opened for #{circuit_id} after #{new_failures} failures"
            )

            %{
              state: :open,
              failures: new_failures,
              last_failure: now,
              half_open_calls: 0
            }
          else
            %{circuit | failures: new_failures, last_failure: now}
          end

        # Increment half-open calls if applicable
        new_circuit =
          if circuit.state == :half_open do
            %{new_circuit | half_open_calls: circuit.half_open_calls + 1}
          else
            new_circuit
          end

        circuits = Map.put(state.circuits, circuit_id, new_circuit)
        {:reply, error, %{state | circuits: circuits}}
    end
  end
end
