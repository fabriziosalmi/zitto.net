defmodule TheCollectiveWeb.Router do
  use TheCollectiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TheCollectiveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TheCollectiveWeb do
    pipe_through :browser

    # Serve The Collective's minimal interface
    get "/", CollectiveController, :index
  end

  scope "/health", TheCollectiveWeb do
    pipe_through :api
    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/metrics", TheCollectiveWeb do
    pipe_through :api
    get "/evolution", MetricsController, :evolution
    get "/state", MetricsController, :state
    get "/peak-history", MetricsController, :peak_history
  end

  # Other scopes may use custom stacks.
  # scope "/api", TheCollectiveWeb do
  #   pipe_through :api
  # end
end
