defmodule TheCollectiveWeb.UserSocket do
  @moduledoc """
  WebSocket handler for The Collective.
  
  This socket module handles all WebSocket connections for The Collective,
  optimized for massive scale with minimal overhead per connection.
  """
  
  use Phoenix.Socket
  require Logger
  
  # Channel route for The Collective
  channel "collective:lobby", TheCollectiveWeb.CollectiveChannel
  
  @doc """
  Socket connection handler.
  
  For The Collective, we don't need individual user authentication
  since all souls are anonymous and ephemeral. We simply allow
  all connections to join.
  """
  @impl true
  def connect(_params, socket, connect_info) do
    # Log connection for monitoring (but keep it minimal for performance)
    peer_data = connect_info[:peer_data]
    Logger.debug("Soul connecting from #{inspect(peer_data)}")
    
    # Allow all connections - The Collective is open to all
    {:ok, socket}
  end
  
  @doc """
  Socket ID generation.
  
  Since we don't track individual users, we return nil to avoid
  creating unnecessary socket identifiers. This optimizes memory usage
  for massive concurrent connections.
  """
  @impl true
  def id(_socket), do: nil
end
