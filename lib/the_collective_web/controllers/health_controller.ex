defmodule TheCollectiveWeb.HealthController do
  use TheCollectiveWeb, :controller
  require Logger

  alias TheCollective.{Redis, Chronos}

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

    status = if redis == "ok" and chronos == "ok", do: 200, else: 503
    json(conn |> put_status(status), %{status: if(status == 200, do: "ready", else: "unready"), redis: redis, chronos: chronos})
  end
end
