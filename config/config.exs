# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :the_collective,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :the_collective, TheCollectiveWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TheCollectiveWeb.ErrorHTML, json: TheCollectiveWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TheCollective.PubSub,
  live_view: [signing_salt: "e1RKvdLU"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  the_collective: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  the_collective: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Redis configuration for The Collective's global state
config :the_collective,
  redis_url: System.get_env("REDIS_URL") || "redis://localhost:6379",
  redis_pool_size: String.to_integer(System.get_env("REDIS_POOL_SIZE") || "10")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
