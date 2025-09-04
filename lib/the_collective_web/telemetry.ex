defmodule TheCollectiveWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # The Collective specific metrics
      last_value("the_collective.concurrent_connections"),
      last_value("the_collective.total_connection_seconds"),
      last_value("the_collective.peak_connections"),
      counter("the_collective.evolution_events.total"),
      counter("the_collective.connections.joined.total"),
      counter("the_collective.connections.left.total"),
      counter("the_collective.backpressure.rejected.total"),
      summary("the_collective.chronos.tick.duration", unit: {:native, :millisecond}),
      summary("the_collective.redis.command.duration", unit: {:native, :millisecond}),
      counter("the_collective.redis.command.errors.total"),
      last_value("the_collective.redis.pool.size"),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :dispatch_collective_metrics, []}
    ]
  end

  @doc """
  Periodically dispatch The Collective metrics to telemetry.
  """
  def dispatch_collective_metrics do
    # Get current state from Redis
    concurrent_connections = TheCollective.Redis.get_int("global:concurrent_connections") || 0
    total_connection_seconds = TheCollective.Redis.get_int("global:total_connection_seconds") || 0
    peak_connections = TheCollective.Redis.get_int("global:peak_connections") || 0

    # Dispatch telemetry events
    :telemetry.execute([:the_collective, :concurrent_connections], %{value: concurrent_connections}, %{})
    :telemetry.execute([:the_collective, :total_connection_seconds], %{value: total_connection_seconds}, %{})
    :telemetry.execute([:the_collective, :peak_connections], %{value: peak_connections}, %{})

    # Get Redis pool size
    redis_pool_size = Application.get_env(:the_collective, :redis_pool_size, 10)
    :telemetry.execute([:the_collective, :redis, :pool, :size], %{value: redis_pool_size}, %{})
  rescue
    error ->
      # Log but don't crash on telemetry errors
      require Logger
      Logger.warning("Failed to dispatch collective metrics: #{inspect(error)}")
  end
end
