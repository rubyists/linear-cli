import Config

# LinearCli.ObanRepo.{Sqlite,Postgres}'s connection details - resolved at
# boot (Mix's `app.config` task loads this before `mix run`/`mix
# test`/`iex -S mix` start the app, and `mix release` runs it fresh on
# every boot, unlike config/config.exs's compile-time config), so a daemon
# restart - not a rebuild - picks up new credentials/host. Both repos are
# always configured here; LinearCli.ObanRepo picks which one actually
# starts, at that same boot (see its moduledoc), so this file doesn't need
# to duplicate that choice - only Postgres's password has no real default,
# since only someone actually using it needs to set one.
default_sqlite_path =
  case config_env() do
    :test -> ":memory:"
    :dev -> Path.expand("../oban_dev.db", __DIR__)
    :prod -> Path.join(System.user_home!(), ".linear_cli/oban.db")
  end

config :linear_cli, LinearCli.ObanRepo.Sqlite, database: default_sqlite_path

default_pg_database =
  case config_env() do
    :test -> "linear_cli_test"
    :dev -> "linear_cli_dev"
    :prod -> "linear_cli"
  end

config :linear_cli, LinearCli.ObanRepo.Postgres,
  hostname: System.get_env("LINEAR_CLI_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("LINEAR_CLI_PG_PORT", "5432")),
  username: System.get_env("LINEAR_CLI_PG_USER", "postgres"),
  password: System.get_env("LINEAR_CLI_PG_PASSWORD", ""),
  database: System.get_env("LINEAR_CLI_PG_DATABASE", default_pg_database)
