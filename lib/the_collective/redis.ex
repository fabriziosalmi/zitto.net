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
      {:ok, value} -> String.to_integer(value)
      {:error, _} -> nil
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
  
  @doc """
  Execute a Redis command using a connection from the pool.
  """
  def command(command) do
    pool_size = Application.get_env(:the_collective, :redis_pool_size, 10)
    connection_name = :"#{@redis_pool_name}_#{Enum.random(1..pool_size)}"
    
    try do
      Redix.command(connection_name, command)
    rescue
      e ->
        Logger.error("Redis command failed: #{inspect(command)}, error: #{inspect(e)}")
        {:error, e}
    end
  end
  
  @doc """
  Execute multiple Redis commands in a pipeline.
  """
  defp pipeline(commands) do
    pool_size = Application.get_env(:the_collective, :redis_pool_size, 10)
    connection_name = :"#{@redis_pool_name}_#{Enum.random(1..pool_size)}"
    
    try do
      Redix.pipeline(connection_name, commands)
    rescue
      e ->
        Logger.error("Redis pipeline failed: #{inspect(commands)}, error: #{inspect(e)}")
        {:error, e}
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
end
