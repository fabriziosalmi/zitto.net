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
  
  For The Collective, we implement backpressure management to handle
  massive scale while maintaining anonymous, ephemeral connections.
  """
  @impl true
  def connect(_params, socket, connect_info) do
    # Extract IP address for rate limiting
    ip_address = get_ip_address(connect_info)
    
    # Check if connection should be allowed (backpressure management)
    case TheCollective.BackpressureManager.check_connection_allowed(ip_address) do
      {:ok, :allowed} ->
        # Check if system is accepting new connections (graceful shutdown)
        case TheCollective.GracefulShutdown.accepting_connections? do
          true ->
            # Log connection for monitoring (but keep it minimal for performance)
            Logger.debug("Soul connecting from #{inspect(ip_address)}")
            
            # Record the connection for backpressure tracking
            TheCollective.BackpressureManager.record_connection(ip_address)
            
            # Allow the connection
            {:ok, assign(socket, :ip_address, ip_address)}
            
          false ->
            Logger.debug("Connection rejected - system shutting down")
            :error
        end
        
      {:error, reason} ->
        Logger.debug("Connection rejected due to backpressure: #{reason}")
        :error
    end
  end
  
  @doc """
  Socket ID generation.
  
  Since we don't track individual users, we return nil to avoid
  creating unnecessary socket identifiers. This optimizes memory usage
  for massive concurrent connections.
  """
  @impl true
  def id(_socket), do: nil
  
  # Private helper to extract IP address from connection info
  defp get_ip_address(connect_info) do
    case connect_info[:peer_data] do
      %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
      %{address: {a, b, c, d, e, f, g, h}} -> 
        # IPv6 address - convert to string representation
        parts = [a, b, c, d, e, f, g, h]
        parts
        |> Enum.map(&Integer.to_string(&1, 16))
        |> Enum.join(":")
      _ -> "unknown"
    end
  end
end
