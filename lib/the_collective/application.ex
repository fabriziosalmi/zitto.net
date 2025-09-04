defmodule TheCollective.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TheCollectiveWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:the_collective, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TheCollective.PubSub},
      # Redis connection pool for global state management
      {TheCollective.Redis, []},
      # Graceful shutdown manager for deployment safety
      {TheCollective.GracefulShutdown, []},
      # Backpressure manager for connection rate limiting
      {TheCollective.BackpressureManager, []},
      # Chronos - The time engine that drives The Collective's evolution
      {TheCollective.Chronos, []},
      # Start to serve requests, typically the last entry
      TheCollectiveWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TheCollective.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TheCollectiveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
