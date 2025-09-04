defmodule TheCollective.BackpressureManagerTest do
  use ExUnit.Case, async: false
  
  alias TheCollective.BackpressureManager
  
  setup do
    # Start the BackpressureManager GenServer for testing
    start_supervised!(BackpressureManager)
    :ok
  end
  
  describe "backpressure management" do
    test "allows connections under normal circumstances" do
      # Should allow initial connections
      assert {:ok, :allowed} = BackpressureManager.check_connection_allowed("192.168.1.1")
      assert {:ok, :allowed} = BackpressureManager.check_connection_allowed("192.168.1.2")
    end
    
    test "tracks connection statistics" do
      stats = BackpressureManager.get_stats()
      
      # Should have expected keys
      assert Map.has_key?(stats, :connections_rejected)
      assert Map.has_key?(stats, :rate_limited_ips)
      assert Map.has_key?(stats, :config)
    end
    
    test "can update configuration at runtime" do
      new_config = %{connections_per_ip_per_minute: 30}
      assert :ok = BackpressureManager.update_config(new_config)
      
      stats = BackpressureManager.get_stats()
      assert stats.config.connections_per_ip_per_minute == 30
    end
    
    test "records connections properly" do
      ip = "192.168.1.100"
      
      # Record a connection
      BackpressureManager.record_connection(ip)
      
      # Should still allow more connections from the same IP
      assert {:ok, :allowed} = BackpressureManager.check_connection_allowed(ip)
    end
    
    test "handles IP rate limiting" do
      ip = "192.168.1.200"
      
      # Get current config to know the limit
      stats = BackpressureManager.get_stats()
      limit = stats.config.connections_per_ip_per_minute
      
      # Record connections up to the limit
      for _i <- 1..limit do
        BackpressureManager.record_connection(ip)
      end
      
      # Should now be rate limited
      assert {:error, :ip_rate_limited} = BackpressureManager.check_connection_allowed(ip)
    end
  end
end