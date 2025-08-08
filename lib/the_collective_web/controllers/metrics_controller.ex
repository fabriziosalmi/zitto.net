defmodule TheCollectiveWeb.MetricsController do
  use TheCollectiveWeb, :controller

  alias TheCollective.{Evolution, Redis, Chronos}

  def evolution(conn, _params) do
    json(conn, Evolution.get_evolution_stats())
  end

  def state(conn, _params) do
    state = %{
      concurrent_connections: Redis.get_int("global:concurrent_connections") || 0,
      total_connection_seconds: Redis.get_int("global:total_connection_seconds") || 0,
      peak_connections: Redis.get_int("global:peak_connections") || 0,
      chronos: Chronos.get_stats()
    }

    json(conn, state)
  end
end
