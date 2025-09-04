import Config

# Helper function for parsing and validating positive integers from environment variables
defp parse_positive_integer(nil, default, _env_name), do: default

defp parse_positive_integer(value, default, env_name) when is_binary(value) do
  case Integer.parse(value) do
    {int_value, ""} when int_value > 0 ->
      int_value
    _ ->
      IO.warn("Invalid value for #{env_name}: '#{value}'. Using default: #{default}")
      default
  end
end

defp parse_positive_integer(_value, default, env_name) do
  IO.warn("Invalid type for #{env_name}. Using default: #{default}")
  default
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/the_collective start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :the_collective, TheCollectiveWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :the_collective, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :the_collective, TheCollectiveWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Configure Redis URL for The Collective's global state
  redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379"
  redis_pool_size = System.get_env("REDIS_POOL_SIZE") |> parse_positive_integer(10, "REDIS_POOL_SIZE")
  
  config :the_collective, :redis_url, redis_url
  config :the_collective, :redis_pool_size, redis_pool_size

  # Configure backpressure management for production
  connections_per_ip = System.get_env("CONNECTIONS_PER_IP_PER_MINUTE") |> parse_positive_integer(60, "CONNECTIONS_PER_IP_PER_MINUTE")
  global_connections_per_sec = System.get_env("GLOBAL_CONNECTIONS_PER_SECOND") |> parse_positive_integer(1000, "GLOBAL_CONNECTIONS_PER_SECOND")
  max_global_connections = System.get_env("MAX_GLOBAL_CONNECTIONS") |> parse_positive_integer(10_000_000, "MAX_GLOBAL_CONNECTIONS")
  
  config :the_collective, :connections_per_ip_per_minute, connections_per_ip
  config :the_collective, :global_connections_per_second, global_connections_per_sec
  config :the_collective, :max_global_connections, max_global_connections

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :the_collective, TheCollectiveWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :the_collective, TheCollectiveWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
