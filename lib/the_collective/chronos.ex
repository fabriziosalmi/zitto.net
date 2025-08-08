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
  
  # Time contribution per tick in seconds
  @time_contribution_per_tick 5
  
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
  
  @doc """
  Handle the periodic tick that drives The Collective's evolution.
  """
  def handle_info(:tick, state) do
    current_time = System.system_time(:millisecond)
    
    # Calculate actual time elapsed since last tick (for accuracy)
    time_elapsed_ms = current_time - state.last_tick_time
    time_elapsed_seconds = div(time_elapsed_ms, 1000)
    
    # Get the number of active connections across all nodes
    active_connections = count_active_connections()
    
    if active_connections > 0 do
      # Calculate time contribution for this interval
      time_contribution = active_connections * max(time_elapsed_seconds, @time_contribution_per_tick)
      
      # Update the global time counter atomically
      case Redis.incrby("global:total_connection_seconds", time_contribution) do
        {:ok, new_total} ->
          Logger.debug("Tick #{state.tick_count + 1}: #{active_connections} souls contributed #{time_contribution} seconds. Total: #{new_total}")
          
          # Check for evolution events after updating the time
          Evolution.check_for_evolution()
          
        {:error, reason} ->
          Logger.error("Failed to update total connection seconds: #{inspect(reason)}")
      end
    else
      Logger.debug("Tick #{state.tick_count + 1}: No active souls to contribute time")
    end
    
    # Schedule the next tick
    schedule_tick()
    
    {:noreply, %{
      tick_count: state.tick_count + 1,
      last_tick_time: current_time
    }}
  end
  
  @doc """
  Handle unexpected messages.
  """
  def handle_info(msg, state) do
    Logger.warning("Chronos received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  @doc """
  Schedule the next tick.
  """
  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end
  
  @doc """
  Count active WebSocket connections across all nodes.
  
  This function uses Phoenix.PubSub to count the number of processes
  subscribed to the "collective:lobby" topic, which represents active
  WebSocket connections.
  """
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
  
  @doc """
  Get current statistics for monitoring.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def handle_call(:get_stats, _from, state) do
    active_connections = count_active_connections()
    total_seconds = Redis.get_int("global:total_connection_seconds") || 0
    
    stats = %{
      tick_count: state.tick_count,
      active_connections: active_connections,
      total_connection_seconds: total_seconds,
      last_tick_time: state.last_tick_time,
      uptime_ms: System.system_time(:millisecond) - (state.last_tick_time - (state.tick_count * @tick_interval))
    }
    
    {:reply, stats, state}
  end
end
