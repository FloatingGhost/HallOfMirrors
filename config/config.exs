# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tesla, :adapter, {Tesla.Adapter.Finch, name: MyFinch}

config :hallofmirrors,
  ecto_repos: [Hallofmirrors.Repo]

# Configures the endpoint
config :hallofmirrors, HallofmirrorsWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "6htkT9APZFNO6TxfRcUxixuoEkvmVwgz/1xvuVmvVzswefmKSrMatHLK6HkktBtH",
  render_errors: [view: HallofmirrorsWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Hallofmirrors.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :extwitter, :oauth,
  consumer_key: "",
  consumer_secret: "",
  access_token: "",
  access_token_secret: ""

config :hallofmirrors, :reddit,
  client_id: "",
  secret: ""

config :hallofmirrors, Hallofmirrors.Scheduler,
  jobs: [
    # Every 15 minutes
    {"*/15 * * * *", {Hallofmirrors.SubredditMirror, :check_all, []}}
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
