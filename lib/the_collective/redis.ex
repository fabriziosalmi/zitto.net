defmodule TheCollective.Redis do
  @moduledoc """
  Redis client module for The Collective.
  
  This module provides a clean interface for all Redis operations
  needed to maintain The Collective's global state.
  """
  
  use GenServer
  require Logger
  
  @redis_pool_name :redis_pool
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    redis_url = Application.get_env(:the_collective, :redis_url, "redis://localhost:6379")
    # Prefer configured pool size to avoid mismatch with command/1 selector
    pool_size = Application.get_env(:the_collective, :redis_pool_size, Keyword.get(opts, :pool_size, 10))
    pool_size = if is_integer(pool_size) and pool_size > 0, do: pool_size, else: 10

    children = for i <- 1..pool_size do
      Supervisor.child_spec(
        {Redix, {redis_url, [name: :"#{@redis_pool_name}_#{i}"]}},
        id: {Redix, i}
      )
    end

    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

    Logger.info("Redis pool started with #{pool_size} connections (#{redis_url})")

    {:ok, %{supervisor: pid, pool_size: pool_size}}
  end
  
  @doc """
  Atomically increment a Redis key and return the new value.
  """
  def incr(key) do
    command(["INCR", key])
  end
  
  @doc """
  Atomically decrement a Redis key and return the new value.
  """
  def decr(key) do
    command(["DECR", key])
  end
  
  @doc """
  Atomically increment a Redis key by a specific amount.
  """
  def incrby(key, amount) do
    command(["INCRBY", key, amount])
  end
  
  @doc """
  Get the value of a Redis key as an integer.
  Returns nil if the key doesn't exist.
  """
  def get_int(key) do
    case command(["GET", key]) do
      {:ok, nil} -> nil
      {:ok, value} when is_binary(value) ->
        case Integer.parse(value) do
          {int_value, ""} -> int_value
          _ -> 
            Logger.warning("Invalid integer value in Redis key #{key}: #{inspect(value)}")
            nil
        end
      {:error, reason} ->
        Logger.warning("Failed to get Redis key #{key}: #{inspect(reason)}")
        nil
    end
  end
  
  @doc """
  Add a member to a Redis set.
  """
  def sadd(key, member) do
    command(["SADD", key, member])
  end
  
  @doc """
  Get all members of a Redis set.
  """
  def smembers(key) do
    command(["SMEMBERS", key])
  end
  
  @doc """
  Check if a member exists in a Redis set.
  """
  def sismember(key, member) do
    case command(["SISMEMBER", key, member]) do
      {:ok, 1} -> true
      {:ok, 0} -> false
      {:error, _} -> false
    end
  end

  @doc """
  Add a member to a Redis sorted set with a score.
  """
  def zadd(key, score, member) do
    command(["ZADD", key, score, member])
  end

  @doc """
  Get members from a sorted set within a score range.
  """
  def zrangebyscore(key, min_score, max_score) do
    command(["ZRANGEBYSCORE", key, min_score, max_score, "WITHSCORES"])
  end

  @doc """
  Remove members from a sorted set that are older than a given score.
  """
  def zremrangebyscore(key, min_score, max_score) do
    command(["ZREMRANGEBYSCORE", key, min_score, max_score])
  end
  
  @doc """
  Set a key-value pair in Redis.
  """
  def set(key, value) do
    command(["SET", key, value])
  end
  
  @doc """
  Get the value of a Redis key.
  """
  def get(key) do
    command(["GET", key])
  end
  
  @doc """
  Execute multiple Redis commands atomically using a transaction.
  """
  def multi(commands) do
    pipeline(["MULTI"] ++ commands ++ ["EXEC"])
  end
  
  # Health check ping
  def ping do
    case command(["PING"]) do
      {:ok, "PONG"} -> :ok
      {:ok, _} -> {:error, :unexpected_pong}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Set cardinality (for fast counts)
  def scard(key) do
    command(["SCARD", key])
  end
  
  def command(redis_command) do
    pool_size = Application.get_env(:the_collective, :redis_pool_size, 10)
    connection_name = select_random_connection(pool_size)
    
    # Add telemetry for monitoring Redis performance
    start_time = System.monotonic_time()
    result = execute_redis_command(connection_name, redis_command)
    end_time = System.monotonic_time()
    
    # Emit telemetry event
    :telemetry.execute(
      [:the_collective, :redis, :command, :duration],
      %{duration: end_time - start_time},
      %{command: List.first(redis_command), result: elem(result, 0)}
    )
    
    result
  end

  defp select_random_connection(pool_size) do
    # Use faster random selection for high-throughput scenarios
    # :rand.uniform is faster than Enum.random for simple cases
    connection_id = :rand.uniform(pool_size)
    :"#{@redis_pool_name}_#{connection_id}"
  end

  defp execute_redis_command(connection_name, redis_command) do
    try do
      Redix.command(connection_name, redis_command)
    rescue
      error ->
        # Emit error telemetry
        :telemetry.execute(
          [:the_collective, :redis, :command, :errors, :total],
          %{count: 1},
          %{command: List.first(redis_command), error: inspect(error)}
        )
        Logger.error("Redis command failed: #{inspect(redis_command)}, error: #{inspect(error)}")
        {:error, error}
    end
  end
  
  # Execute multiple Redis commands in a pipeline (private)
  defp pipeline(commands) do
    pool_size = Application.get_env(:the_collective, :redis_pool_size, 10)
    connection_name = select_random_connection(pool_size)
    
    execute_redis_pipeline(connection_name, commands)
  end

  defp execute_redis_pipeline(connection_name, commands) do
    try do
      Redix.pipeline(connection_name, commands)
    rescue
      error ->
        Logger.error("Redis pipeline failed: #{inspect(commands)}, error: #{inspect(error)}")
        {:error, error}
    end
  end
  
  @doc """
  Initialize the global state keys in Redis if they don't exist.
  """
  def initialize_global_state do
    Logger.info("Initializing global state in Redis")
    
    # Initialize concurrent connections to 0 if not exists
    case get("global:concurrent_connections") do
      {:ok, nil} -> set("global:concurrent_connections", "0")
      _ -> :ok
    end
    
    # Initialize total connection seconds to 0 if not exists
    case get("global:total_connection_seconds") do
      {:ok, nil} -> set("global:total_connection_seconds", "0")
      _ -> :ok
    end

    # Initialize peak connections to 0 if not exists
    case get("global:peak_connections") do
      {:ok, nil} -> set("global:peak_connections", "0")
      _ -> :ok
    end
    
    Logger.info("Global state initialized")
  end

  @doc """
  Record a peak connection count with timestamp for historical tracking.
  """
  def record_peak_history(peak_count) do
    timestamp = System.system_time(:second)
    zadd("global:peak_history", timestamp, "#{timestamp}:#{peak_count}")
    
    # Clean old entries (keep only last 7 days for performance)
    seven_days_ago = timestamp - (7 * 24 * 60 * 60)
    zremrangebyscore("global:peak_history", "-inf", seven_days_ago)
  end

  @doc """
  Get peak connection history for the last 24 hours.
  Returns a list of {timestamp, peak_value} tuples.
  """
  def get_peak_history_24h do
    now = System.system_time(:second)
    twenty_four_hours_ago = now - (24 * 60 * 60)
    
    case zrangebyscore("global:peak_history", twenty_four_hours_ago, "+inf") do
      {:ok, raw_data} when is_list(raw_data) ->
        parse_peak_history_data(raw_data)
      _ -> 
        []
    end
  end

  defp parse_peak_history_data(raw_data) when is_list(raw_data) do
    # Parse the data: ["timestamp:value", "score", ...]
    try do
      raw_data
      |> Enum.chunk_every(2)
      |> Enum.map(&parse_peak_history_entry/1)
      |> Enum.filter(fn {timestamp, _peak_value} -> timestamp > 0 end)
      |> Enum.sort_by(fn {timestamp, _peak_value} -> timestamp end)
    rescue
      error ->
        Logger.error("Failed to parse peak history data: #{inspect(error)}")
        []
    end
  end

  defp parse_peak_history_data(_invalid_data) do
    Logger.warning("Invalid peak history data received")
    []
  end

  defp parse_peak_history_entry([entry, score]) when is_binary(entry) and is_binary(score) do
    case String.split(entry, ":", parts: 2) do
      [_timestamp_str, value_str] ->
        with {timestamp, ""} <- Integer.parse(score),
             {value, ""} <- Integer.parse(value_str) do
          {timestamp, value}
        else
          _ ->
            Logger.warning("Invalid peak history entry format: #{inspect(entry)} with score #{inspect(score)}")
            {0, 0}
        end
      _ ->
        Logger.warning("Invalid peak history entry format: #{inspect(entry)}")
        {0, 0}
    end
  end

  defp parse_peak_history_entry(invalid_entry) do
    Logger.warning("Invalid peak history entry structure: #{inspect(invalid_entry)}")
    {0, 0}
  end
end
