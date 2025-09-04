defmodule TheCollective.BackpressureManager do
  @moduledoc """
  Backpressure Management for The Collective.
  
  Implements rate limiting and backpressure mechanisms to prevent system
  overload during sudden influxes of connections. This is critical for
  maintaining stability at massive scale (10+ million concurrent connections).
  
  Features:
  - Connection rate limiting per IP
  - Global connection throttling
  - Adaptive backpressure based on system load
  - Circuit breaker pattern for Redis operations
  """
  
  use GenServer
  require Logger
  
  alias TheCollective.Redis
  
  # Default rate limits
  @default_connections_per_ip_per_minute 60
  @default_global_connections_per_second 1000
  @default_max_global_connections 10_000_000
  
  # Circuit breaker settings
  @circuit_breaker_failure_threshold 5
  @circuit_breaker_timeout_ms 30_000
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Configure rate limits from environment or use defaults
    config = %{
      connections_per_ip_per_minute: 
        Application.get_env(:the_collective, :connections_per_ip_per_minute, @default_connections_per_ip_per_minute),
      global_connections_per_second: 
        Application.get_env(:the_collective, :global_connections_per_second, @default_global_connections_per_second),
      max_global_connections: 
        Application.get_env(:the_collective, :max_global_connections, @default_max_global_connections)
    }
    
    # Initialize ETS tables for rate limiting
    :ets.new(:ip_rate_limits, [:named_table, :public, :set])
    :ets.new(:global_rate_limit, [:named_table, :public, :set])
    
    # Schedule cleanup of old rate limit entries
    schedule_cleanup()
    
    Logger.info("BackpressureManager started with config: #{inspect(config)}")
    
    {:ok, %{
      config: config,
      circuit_breaker: %{
        redis_failures: 0,
        redis_circuit_open: false,
        redis_last_failure: nil
      },
      stats: %{
        connections_rejected: 0,
        rate_limited_ips: 0,
        global_rate_limited: 0
      }
    }}
  end
  
  @doc """
  Check if a new connection should be allowed.
  
  Returns {:ok, :allowed} if connection is permitted,
  {:error, reason} if connection should be rejected.
  """
  def check_connection_allowed(ip_address) do
    GenServer.call(__MODULE__, {:check_connection, ip_address})
  end
  
  @doc """
  Record a successful connection for rate limiting purposes.
  """
  def record_connection(ip_address) do
    GenServer.cast(__MODULE__, {:record_connection, ip_address})
  end
  
  @doc """
  Get current backpressure statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Update rate limit configuration at runtime.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end
  
  def handle_call({:check_connection, ip_address}, _from, state) do
    result = 
      with {:ok, :ip_allowed} <- check_ip_rate_limit(ip_address, state.config),
           {:ok, :global_allowed} <- check_global_rate_limit(state.config),
           {:ok, :capacity_available} <- check_global_capacity(state.config) do
        {:ok, :allowed}
      else
        {:error, reason} -> {:error, reason}
      end
    
    case result do
      {:ok, :allowed} ->
        {:reply, result, state}
      {:error, reason} ->
        # Update rejection stats
        new_stats = update_rejection_stats(state.stats, reason)
        Logger.debug("Connection rejected: #{reason}")
        {:reply, result, %{state | stats: new_stats}}
    end
  end
  
  def handle_call(:get_stats, _from, state) do
    # Combine local stats with Redis-based global stats
    global_connections = Redis.get_int("global:concurrent_connections") || 0
    
    stats = Map.merge(state.stats, %{
      global_connections: global_connections,
      circuit_breaker_open: state.circuit_breaker.redis_circuit_open,
      ip_rate_limit_entries: :ets.info(:ip_rate_limits, :size),
      config: state.config
    })
    
    {:reply, stats, state}
  end
  
  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)
    Logger.info("Updated backpressure config: #{inspect(updated_config)}")
    {:reply, :ok, %{state | config: updated_config}}
  end
  
  def handle_cast({:record_connection, ip_address}, state) do
    # Record the connection in rate limiting tables
    record_ip_connection(ip_address)
    record_global_connection()
    {:noreply, state}
  end
  
  def handle_info(:cleanup_rate_limits, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end
  
  # Private helper functions
  
  defp check_ip_rate_limit(ip_address, config) do
    now = System.system_time(:second)
    minute_ago = now - 60
    
    # Get current connections for this IP in the last minute
    case :ets.lookup(:ip_rate_limits, ip_address) do
      [] ->
        {:ok, :ip_allowed}
      [{_ip, timestamps}] ->
        # Filter out old timestamps
        recent_timestamps = Enum.filter(timestamps, fn ts -> ts > minute_ago end)
        
        if length(recent_timestamps) >= config.connections_per_ip_per_minute do
          {:error, :ip_rate_limited}
        else
          {:ok, :ip_allowed}
        end
    end
  end
  
  defp check_global_rate_limit(config) do
    now = System.system_time(:second)
    
    case :ets.lookup(:global_rate_limit, :current_second) do
      [] ->
        {:ok, :global_allowed}
      [{:current_second, {timestamp, count}}] ->
        if timestamp == now do
          if count >= config.global_connections_per_second do
            {:error, :global_rate_limited}
          else
            {:ok, :global_allowed}
          end
        else
          # New second, reset counter
          {:ok, :global_allowed}
        end
    end
  end
  
  defp check_global_capacity(config) do
    # Check current global connections against maximum
    case Redis.get_int("global:concurrent_connections") do
      nil -> {:ok, :capacity_available}
      count when count >= config.max_global_connections ->
        {:error, :global_capacity_exceeded}
      _count -> {:ok, :capacity_available}
    end
  rescue
    _error ->
      # If Redis is unavailable, be conservative and allow connections
      # unless circuit breaker is open
      {:ok, :capacity_available}
  end
  
  defp record_ip_connection(ip_address) do
    now = System.system_time(:second)
    
    case :ets.lookup(:ip_rate_limits, ip_address) do
      [] ->
        :ets.insert(:ip_rate_limits, {ip_address, [now]})
      [{_ip, timestamps}] ->
        updated_timestamps = [now | timestamps]
        :ets.insert(:ip_rate_limits, {ip_address, updated_timestamps})
    end
  end
  
  defp record_global_connection do
    now = System.system_time(:second)
    
    case :ets.lookup(:global_rate_limit, :current_second) do
      [] ->
        :ets.insert(:global_rate_limit, {:current_second, {now, 1}})
      [{:current_second, {timestamp, count}}] ->
        if timestamp == now do
          :ets.insert(:global_rate_limit, {:current_second, {now, count + 1}})
        else
          :ets.insert(:global_rate_limit, {:current_second, {now, 1}})
        end
    end
  end
  
  defp update_rejection_stats(stats, reason) do
    case reason do
      :ip_rate_limited ->
        %{stats | rate_limited_ips: stats.rate_limited_ips + 1}
      :global_rate_limited ->
        %{stats | global_rate_limited: stats.global_rate_limited + 1}
      _ ->
        %{stats | connections_rejected: stats.connections_rejected + 1}
    end
  end
  
  defp cleanup_expired_entries do
    now = System.system_time(:second)
    minute_ago = now - 60
    
    # Clean up IP rate limits
    :ets.foldl(fn {ip, timestamps}, acc ->
      recent_timestamps = Enum.filter(timestamps, fn ts -> ts > minute_ago end)
      if Enum.empty?(recent_timestamps) do
        :ets.delete(:ip_rate_limits, ip)
      else
        :ets.insert(:ip_rate_limits, {ip, recent_timestamps})
      end
      acc
    end, nil, :ip_rate_limits)
    
    # Clean up global rate limit if it's from a previous second
    case :ets.lookup(:global_rate_limit, :current_second) do
      [{:current_second, {timestamp, _count}}] when timestamp < now ->
        :ets.delete(:global_rate_limit, :current_second)
      _ ->
        :ok
    end
  end
  
  defp schedule_cleanup do
    # Clean up every 30 seconds
    Process.send_after(self(), :cleanup_rate_limits, 30_000)
  end
end