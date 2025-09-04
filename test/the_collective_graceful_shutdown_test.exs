defmodule TheCollective.GracefulShutdownTest do
  use ExUnit.Case, async: false
  
  alias TheCollective.GracefulShutdown
  
  setup do
    # Start the GracefulShutdown GenServer for testing
    start_supervised!(GracefulShutdown)
    :ok
  end
  
  describe "graceful shutdown functionality" do
    test "initially accepts connections" do
      assert GracefulShutdown.accepting_connections?() == true
    end
    
    test "tracks active connections" do
      # Register a few connections
      GracefulShutdown.register_connection()
      GracefulShutdown.register_connection()
      GracefulShutdown.register_connection()
      
      # Unregister one
      GracefulShutdown.unregister_connection()
      
      # Should still be accepting connections
      assert GracefulShutdown.accepting_connections?() == true
    end
    
    test "stops accepting connections during shutdown" do
      # Initiate shutdown
      assert GracefulShutdown.initiate_shutdown() == :ok
      
      # Should no longer accept connections
      assert GracefulShutdown.accepting_connections?() == false
      
      # Multiple shutdown initiations should be safe
      assert GracefulShutdown.initiate_shutdown() == :already_shutting_down
    end
    
    test "handles connection registration and unregistration" do
      # These should not crash
      GracefulShutdown.register_connection()
      GracefulShutdown.unregister_connection()
      
      # Multiple unregistrations should be safe (clamped to 0)
      GracefulShutdown.unregister_connection()
      GracefulShutdown.unregister_connection()
    end
  end
end