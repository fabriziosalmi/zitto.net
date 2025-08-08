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
        
        # Store the connection count in socket assigns and mark as joined immediately
        socket =
          socket
          |> assign(:current_connections, new_count)
          |> assign(:joined, true)
        
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

    # Update peak connections if a new peak is reached
    current_peak = Redis.get_int("global:peak_connections") || 0
    if socket.assigns.current_connections > current_peak do
      Redis.set("global:peak_connections", socket.assigns.current_connections)
    end

    # Get the current global state and send it to the newly joined soul
    current_state = get_current_global_state()
    push(socket, "welcome", current_state)

    # Broadcast the connection update to all other souls
    broadcast_state_update(socket, current_state)

    {:noreply, socket}
  end
  
  @doc """
  Handle broadcasting state updates to other connected souls.
  """
  def handle_info({:broadcast_state_update, state}, socket) do
    broadcast_from(socket, "state_update", %{
      concurrent_connections: state.concurrent_connections,
      total_connection_seconds: state.total_connection_seconds,
      peak_connections: state.peak_connections
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

    if socket.assigns[:joined] do
      case Redis.decr("global:concurrent_connections") do
        {:ok, new_count} when is_integer(new_count) and new_count >= 0 ->
          Logger.info("Concurrent connections after departure: #{new_count}")
          current_state = get_current_global_state()
          broadcast_state_update(socket, current_state)
        {:ok, negative} ->
          # Clamp to zero on underflow
          Redis.set("global:concurrent_connections", "0")
          Logger.warning("Connection count went negative (#{inspect(negative)}), reset to 0")
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
    peak_connections = Redis.get_int("global:peak_connections") || 0
    
    %{
      concurrent_connections: concurrent_connections,
      total_connection_seconds: total_connection_seconds,
      unlocked_milestones: unlocked_milestones,
      peak_connections: peak_connections
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
      total_connection_seconds: state.total_connection_seconds,
      peak_connections: state.peak_connections
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
