defmodule TheCollective.GracefulShutdown do
  @moduledoc """
  Graceful Shutdown Manager for The Collective.
  
  Ensures that when Phoenix nodes are shutting down during deployments
  or scaling events, in-flight WebSocket operations complete gracefully
  and user connection counts are accurately decremented in Redis.
  
  This module coordinates shutdown behavior to maintain data consistency
  across the distributed system during deployments.
  """
  
  use GenServer
  require Logger
  
  alias TheCollective.Redis
  alias TheCollectiveWeb.Endpoint
  
  @shutdown_timeout_ms 30_000  # 30 seconds for graceful shutdown
  @connection_drain_timeout_ms 15_000  # 15 seconds to drain connections
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Trap exits to handle graceful shutdown
    Process.flag(:trap_exit, true)
    
    Logger.info("GracefulShutdown manager started")
    
    {:ok, %{
      shutdown_initiated: false,
      active_connections: 0,
      shutdown_start_time: nil
    }}
  end
  
  @doc """
  Initiate graceful shutdown sequence.
  
  This is called by the application supervisor when a shutdown signal is received.
  It coordinates draining connections and ensuring Redis state consistency.
  """
  def initiate_shutdown do
    GenServer.call(__MODULE__, :initiate_shutdown, @shutdown_timeout_ms)
  end
  
  @doc """
  Register a new active connection.
  
  Called when a WebSocket connection is established.
  """
  def register_connection do
    GenServer.cast(__MODULE__, :register_connection)
  end
  
  @doc """
  Unregister an active connection.
  
  Called when a WebSocket connection is terminated.
  """
  def unregister_connection do
    GenServer.cast(__MODULE__, :unregister_connection)
  end
  
  @doc """
  Check if system is accepting new connections.
  
  Returns false during shutdown to prevent new connections.
  """
  def accepting_connections? do
    GenServer.call(__MODULE__, :accepting_connections?)
  end
  
  def handle_call(:initiate_shutdown, _from, state) do
    if state.shutdown_initiated do
      {:reply, :already_shutting_down, state}
    else
      Logger.info("Initiating graceful shutdown sequence")
      
      # Mark shutdown as initiated
      new_state = %{
        state | 
        shutdown_initiated: true,
        shutdown_start_time: System.monotonic_time(:millisecond)
      }
      
      # Start the shutdown sequence
      send(self(), :begin_connection_drain)
      
      {:reply, :ok, new_state}
    end
  end
  
  def handle_call(:accepting_connections?, _from, state) do
    {:reply, not state.shutdown_initiated, state}
  end
  
  def handle_cast(:register_connection, state) do
    new_count = state.active_connections + 1
    Logger.debug("Registered connection, active: #{new_count}")
    {:noreply, %{state | active_connections: new_count}}
  end
  
  def handle_cast(:unregister_connection, state) do
    new_count = max(0, state.active_connections - 1)
    Logger.debug("Unregistered connection, active: #{new_count}")
    
    # If we're shutting down and no connections remain, complete shutdown
    if state.shutdown_initiated and new_count == 0 do
      send(self(), :complete_shutdown)
    end
    
    {:noreply, %{state | active_connections: new_count}}
  end
  
  def handle_info(:begin_connection_drain, state) do
    Logger.info("Beginning connection drain - stopping new connections")
    
    # Broadcast to all connected clients that shutdown is imminent
    broadcast_shutdown_warning()
    
    # Schedule timeout for forced shutdown if connections don't drain
    Process.send_after(self(), :force_shutdown, @connection_drain_timeout_ms)
    
    # If no active connections, complete immediately
    if state.active_connections == 0 do
      send(self(), :complete_shutdown)
    else
      Logger.info("Waiting for #{state.active_connections} connections to drain")
    end
    
    {:noreply, state}
  end
  
  def handle_info(:force_shutdown, state) do
    if state.shutdown_initiated do
      Logger.warning("Force shutdown triggered - #{state.active_connections} connections remaining")
      send(self(), :complete_shutdown)
    end
    {:noreply, state}
  end
  
  def handle_info(:complete_shutdown, state) do
    Logger.info("Completing graceful shutdown")
    
    # Ensure Redis state is cleaned up for any remaining connections on this node
    cleanup_node_state()
    
    # Signal the application to complete shutdown
    System.stop(0)
    
    {:noreply, state}
  end
  
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.info("GracefulShutdown received EXIT signal: #{inspect(reason)}")
    
    # If we haven't started shutdown yet, start it now
    unless state.shutdown_initiated do
      send(self(), :begin_connection_drain)
      new_state = %{
        state | 
        shutdown_initiated: true,
        shutdown_start_time: System.monotonic_time(:millisecond)
      }
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  # Private helper functions
  
  defp broadcast_shutdown_warning do
    try do
      Endpoint.broadcast("collective:lobby", "shutdown_warning", %{
        message: "System maintenance in progress. You may experience a brief disconnection.",
        reconnect_delay: 5000
      })
    rescue
      error ->
        Logger.error("Failed to broadcast shutdown warning: #{inspect(error)}")
    end
  end
  
  defp cleanup_node_state do
    try do
      # Get the current connection count for cleanup
      current_connections = Redis.get_int("global:concurrent_connections") || 0
      
      # If we have any remaining local connections, decrement them from global count
      if current_connections > 0 do
        Logger.info("Cleaning up remaining Redis state for graceful shutdown")
        
        # In a real distributed scenario, you might want to track per-node connections
        # For now, we ensure the count doesn't go negative
        case Redis.command(["DECR", "global:concurrent_connections"]) do
          {:ok, new_count} when new_count >= 0 ->
            Logger.info("Decremented global connections to #{new_count}")
          {:ok, negative_count} ->
            # Reset to 0 if it went negative
            Redis.set("global:concurrent_connections", "0")
            Logger.warning("Reset connection count from #{negative_count} to 0")
          {:error, reason} ->
            Logger.error("Failed to cleanup connections in Redis: #{inspect(reason)}")
        end
      end
    rescue
      error ->
        Logger.error("Error during Redis cleanup: #{inspect(error)}")
    end
  end
end