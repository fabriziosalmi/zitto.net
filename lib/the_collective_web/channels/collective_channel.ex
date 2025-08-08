defmodule TheCollectiveWeb.CollectiveChannel do
  @moduledoc """
  Phoenix Channel for handling The Collective's WebSocket connections.
  
  This is the single entry point for all WebSocket connections to The Collective.
  It manages the global state in Redis and coordinates real-time communication
  between all connected souls.
  """
  
  use Phoenix.Channel
  require Logger
  
  alias TheCollective.Redis
  alias TheCollective.Evolution
  
  @doc """
  Authorize and join the collective:lobby topic.
  
  This function handles the initial connection to The Collective, updates
  global counters, and sends the current state to the newly connected soul.
  """
  def join("collective:lobby", _params, socket) do
    Logger.info("Soul joining The Collective from #{inspect(socket.assigns)}")
    
    # Increment the concurrent connections counter atomically
    case Redis.incr("global:concurrent_connections") do
      {:ok, new_count} ->
        Logger.info("Concurrent connections: #{new_count}")
        
        # Get current global state for welcome message
        current_state = get_current_global_state()
        
        # Schedule post-join operations to happen after the join is complete
        send(self(), {:after_join})
        
        {:ok, socket}
        
      {:error, reason} ->
        Logger.error("Failed to increment connections counter: #{inspect(reason)}")
        {:error, %{reason: "collective_unavailable"}}
    end
  end
  
  @doc """
  Handle unauthorized join attempts to other topics.
  """
  def join(_topic, _params, _socket) do
    {:error, %{reason: "unauthorized"}}
  end
  
  @doc """
  Handle post-join operations.
  
  Sends the welcome message with current global state to the newly connected soul.
  """
  def handle_info({:after_join}, socket) do
    Logger.info("Concurrent connections: #{socket.assigns.current_connections}")
    
    # Check for milestone achievements
    TheCollective.Evolution.check_milestones(socket.assigns.current_connections)
    
    # Get the current global state and send it to the newly joined soul
    current_state = get_current_global_state()
    push(socket, "state_update", current_state)
    
    # Broadcast the connection update to all other souls
    broadcast_state_update(socket, current_state)
    
    # Mark this socket as fully joined
    socket = assign(socket, :joined, true)
    
    {:noreply, socket}
  end
  
  @doc """
  Handle broadcasting state updates to other connected souls.
  """
  def handle_info({:broadcast_state_update, state}, socket) do
    broadcast_from(socket, "state_update", %{
      concurrent_connections: state.concurrent_connections,
      total_connection_seconds: state.total_connection_seconds
    })
    {:noreply, socket}
  end
  
  @doc """
  Handle channel termination.
  
  When a soul disconnects from The Collective, this function decrements
  the global connection counter and broadcasts the updated state.
  """
  def terminate(_reason, socket) do
    Logger.info("Soul leaving The Collective")
    
    # Only decrement if this socket was properly joined (has the :joined flag)
    if socket.assigns[:joined] do
      # Decrement the concurrent connections counter atomically, but not below 0
      case Redis.command(["DECR", "global:concurrent_connections"]) do
        {:ok, new_count} when new_count >= 0 ->
          Logger.info("Concurrent connections after departure: #{new_count}")
          
          # Broadcast the updated count to all remaining souls
          current_state = get_current_global_state()
          broadcast_state_update(socket, current_state)
          
        {:ok, negative_count} ->
          # Reset to 0 if it went negative
          Redis.command(["SET", "global:concurrent_connections", "0"])
          Logger.warn("Connection count went negative (#{negative_count}), reset to 0")
          
        {:error, reason} ->
          Logger.error("Failed to decrement connections counter: #{inspect(reason)}")
      end
    else
      Logger.debug("Soul left before fully joining, no decrement needed")
    end
    
    :ok
  end
  
  @doc """
  Get the current global state from Redis.
  
  Returns a map containing:
  - concurrent_connections: Current number of active WebSocket connections
  - total_connection_seconds: Total accumulated connection time
  - unlocked_milestones: List of achieved evolution milestones
  """
  defp get_current_global_state do
    concurrent_connections = Redis.get_int("global:concurrent_connections") || 0
    total_connection_seconds = Redis.get_int("global:total_connection_seconds") || 0
    unlocked_milestones = get_unlocked_milestones()
    
    %{
      concurrent_connections: concurrent_connections,
      total_connection_seconds: total_connection_seconds,
      unlocked_milestones: unlocked_milestones
    }
  end
  
  @doc """
  Get the list of unlocked milestones from Redis.
  """
  defp get_unlocked_milestones do
    case Redis.smembers("global:unlocked_milestones") do
      {:ok, milestone_ids} ->
        milestone_ids
        |> Enum.map(&Evolution.get_milestone_details/1)
        |> Enum.reject(&is_nil/1)
        
      {:error, _} ->
        []
    end
  end
  
  @doc """
  Broadcast state update to all souls in the collective:lobby.
  """
  defp broadcast_state_update(socket, state) do
    broadcast_from(socket, "state_update", %{
      concurrent_connections: state.concurrent_connections,
      total_connection_seconds: state.total_connection_seconds
    })
  end
  
  @doc """
  Broadcast evolution event to all souls.
  
  This function is called by the Evolution module when a new milestone
  is achieved. It triggers the evolution flash and milestone display
  across all connected clients.
  """
  def broadcast_evolution_event(milestone) do
    Logger.info("Broadcasting evolution event: #{milestone.id}")
    
    TheCollectiveWeb.Endpoint.broadcast("collective:lobby", "evolution_event", %{
      milestone: milestone
    })
  end
end
