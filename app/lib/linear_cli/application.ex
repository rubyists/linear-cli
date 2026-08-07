defmodule LinearCli.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = daemon_children()

    opts = [strategy: :one_for_one, name: LinearCli.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Only the daemon run mode (LINEAR_CLI_DAEMON=true, set by the mix
  # release's daemon startup, never by the interactive escript/Burrito
  # binary) starts the repo + Oban. Confirmed empirically that the escript
  # boots this whole application on every invocation - without this gate,
  # every interactive command would also open a database connection and
  # boot Oban's full supervision tree. See documents/phase-7-plan.adoc.
  #
  # Which repo/engine actually starts is resolved fresh on every boot via
  # LinearCli.ObanRepo.{repo,oban_engine}/0, not baked in at compile time -
  # see that module's moduledoc for why this has to be a runtime choice.
  defp daemon_children do
    if System.get_env("LINEAR_CLI_DAEMON") == "true" do
      repo = LinearCli.ObanRepo.repo()
      ensure_db_ready!(repo)

      oban_opts =
        :linear_cli
        |> Application.fetch_env!(Oban)
        |> Keyword.merge(repo: repo, engine: LinearCli.ObanRepo.oban_engine())

      [repo, {Oban, oban_opts}]
    else
      []
    end
  end

  # Only SQLite needs its containing directory prepared before connecting -
  # Postgres's :database config is a database name, not a filesystem path.
  defp ensure_db_ready!(LinearCli.ObanRepo.Sqlite) do
    :linear_cli
    |> Application.fetch_env!(LinearCli.ObanRepo.Sqlite)
    |> Keyword.fetch!(:database)
    |> Path.dirname()
    |> File.mkdir_p!()
  end

  defp ensure_db_ready!(_repo), do: :ok
end
