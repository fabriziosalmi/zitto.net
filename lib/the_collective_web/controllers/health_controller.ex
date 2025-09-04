defmodule TheCollectiveWeb.HealthController do
  use TheCollectiveWeb, :controller
  require Logger

  alias TheCollective.{Redis, Chronos, GracefulShutdown, BackpressureManager}

  # Simple liveness: endpoint responding
  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  # Readiness: confirm Redis reachable and Chronos responding
  def ready(conn, _params) do
    redis = case Redis.ping() do
      :ok -> "ok"
      {:error, _} -> "error"
    end

    # Try to fetch stats from Chronos; if it crashes just flag error
    chronos = try do
      _ = Chronos.get_stats()
      "ok"
    rescue
      _ -> "error"
    catch
      _, _ -> "error"
    end

    # Check if system is accepting connections (graceful shutdown status)
    accepting_connections = GracefulShutdown.accepting_connections?()

    status = if redis == "ok" and chronos == "ok" and accepting_connections, do: 200, else: 503
    json(conn |> put_status(status), %{
      status: if(status == 200, do: "ready", else: "unready"), 
      redis: redis, 
      chronos: chronos,
      accepting_connections: accepting_connections
    })
  end

  # Detailed system status including backpressure metrics
  def status(conn, _params) do
    # Get backpressure statistics
    backpressure_stats = try do
      BackpressureManager.get_stats()
    rescue
      _ -> %{error: "backpressure_manager_unavailable"}
    end

    # Get graceful shutdown status
    shutdown_status = %{
      accepting_connections: GracefulShutdown.accepting_connections?()
    }

    # Get Redis connection info
    redis_status = case Redis.ping() do
      :ok -> 
        %{
          status: "ok",
          concurrent_connections: Redis.get_int("global:concurrent_connections") || 0,
          total_connection_seconds: Redis.get_int("global:total_connection_seconds") || 0,
          peak_connections: Redis.get_int("global:peak_connections") || 0
        }
      {:error, reason} -> 
        %{status: "error", reason: reason}
    end

    # Get Chronos stats
    chronos_stats = try do
      Chronos.get_stats()
    rescue
      _ -> %{error: "chronos_unavailable"}
    end

    json(conn, %{
      timestamp: DateTime.utc_now(),
      redis: redis_status,
      chronos: chronos_stats,
      backpressure: backpressure_stats,
      graceful_shutdown: shutdown_status
    })
  end
end
