defmodule TheCollective.Chronos do
  @moduledoc """
  The Time Engine of The Collective.
  
  Chronos is a GenServer that acts as the heartbeat of The Collective's evolution.
  It periodically calculates the time contribution from all connected souls
  and updates the global state, triggering evolution events when milestones are reached.
  """
  
  use GenServer
  require Logger
  
  alias TheCollective.Redis
  alias TheCollective.Evolution
  
  # Tick interval in milliseconds (5 seconds)
  @tick_interval 5_000
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    Logger.info("Chronos starting - The heartbeat of The Collective begins")
    
    # Initialize Redis global state
    Redis.initialize_global_state()
    
    # Schedule the first tick
    schedule_tick()
    
    {:ok, %{
      tick_count: 0,
      last_tick_time: System.system_time(:millisecond)
    }}
  end
  
  def handle_info(:tick, state) do
    tick_start_time = System.monotonic_time()
    current_time = System.system_time(:millisecond)
    elapsed_milliseconds = current_time - state.last_tick_time
    elapsed_seconds = calculate_elapsed_seconds(elapsed_milliseconds)
    active_connections = count_active_connections()

    process_tick_contribution(active_connections, elapsed_seconds, state.tick_count + 1)
    schedule_tick()

    # Emit telemetry for tick performance
    tick_duration = System.monotonic_time() - tick_start_time
    :telemetry.execute(
      [:the_collective, :chronos, :tick, :duration],
      %{duration: tick_duration},
      %{active_connections: active_connections, tick_count: state.tick_count + 1}
    )

    {:noreply, %{
      tick_count: state.tick_count + 1,
      last_tick_time: current_time
    }}
  end
  
  def handle_info(msg, state) do
    Logger.warning("Chronos received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp calculate_elapsed_seconds(elapsed_milliseconds) when is_integer(elapsed_milliseconds) and elapsed_milliseconds >= 0 do
    max(div(elapsed_milliseconds, 1000), 1)
  end

  defp calculate_elapsed_seconds(_invalid_elapsed) do
    Logger.warning("Invalid elapsed milliseconds value, using default")
    1
  end

  defp process_tick_contribution(active_connections, elapsed_seconds, tick_number) 
       when is_integer(active_connections) and is_integer(elapsed_seconds) and active_connections >= 0 do
    if active_connections > 0 do
      time_contribution = calculate_time_contribution(active_connections, elapsed_seconds)
      update_global_time_counter(time_contribution, active_connections, tick_number)
    else
      Logger.debug("Tick #{tick_number}: No active souls to contribute time")
    end
  end

  defp process_tick_contribution(active_connections, elapsed_seconds, tick_number) do
    Logger.warning("Invalid tick contribution parameters: connections=#{inspect(active_connections)}, elapsed=#{inspect(elapsed_seconds)}, tick=#{tick_number}")
  end

  defp calculate_time_contribution(active_connections, elapsed_seconds) 
       when is_integer(active_connections) and is_integer(elapsed_seconds) and 
            active_connections >= 0 and elapsed_seconds >= 0 do
    active_connections * max(elapsed_seconds, div(@tick_interval, 1000))
  end

  defp calculate_time_contribution(active_connections, elapsed_seconds) do
    Logger.warning("Invalid time contribution parameters: connections=#{inspect(active_connections)}, elapsed=#{inspect(elapsed_seconds)}")
    0
  end

  defp update_global_time_counter(time_contribution, active_connections, tick_number) do
    case Redis.incrby("global:total_connection_seconds", time_contribution) do
      {:ok, updated_total} ->
        Logger.debug("Tick #{tick_number}: #{active_connections} souls contributed #{time_contribution} seconds. Total: #{updated_total}")
        Evolution.check_for_evolution()
        broadcast_total_time(updated_total)
      {:error, reason} ->
        Logger.error("Failed to update total connection seconds: #{inspect(reason)}")
    end
  end
  
  defp count_active_connections do
    try do
      # Use Phoenix's presence tracking or fallback to Redis counter
      # In production, you might want to use Phoenix.Presence for more accurate tracking
      Redis.get_int("global:concurrent_connections") || 0
    rescue
      error ->
        Logger.warning("Failed to count active connections: #{inspect(error)}")
        0
    end
  end
  
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def handle_call(:get_stats, _from, state) do
    current_connections = count_active_connections()
    total_connection_seconds = Redis.get_int("global:total_connection_seconds") || 0

    statistics = %{
      tick_count: state.tick_count,
      active_connections: current_connections,
      total_connection_seconds: total_connection_seconds,
      last_tick_time: state.last_tick_time,
      uptime_ms: System.system_time(:millisecond) - (state.last_tick_time - (state.tick_count * @tick_interval))
    }

    {:reply, statistics, state}
  end

  defp broadcast_total_time(total_seconds) do
    current_state = build_broadcast_state(total_seconds)

    TheCollectiveWeb.Endpoint.broadcast("collective:lobby", "state_update", %{
      concurrent_connections: current_state.concurrent_connections,
      total_connection_seconds: current_state.total_connection_seconds,
      peak_connections: current_state.peak_connections
    })
  end

  defp build_broadcast_state(total_seconds) do
    %{
      concurrent_connections: Redis.get_int("global:concurrent_connections") || 0,
      total_connection_seconds: total_seconds,
      peak_connections: Redis.get_int("global:peak_connections") || 0
    }
  end
end
