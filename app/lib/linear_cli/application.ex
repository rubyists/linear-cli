defmodule LinearCli.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if System.get_env("LINEAR_CLI_DAEMON") == "true" do
      start_daemon()
    else
      start_interactive()
    end
  end

  # Only the daemon run mode (LINEAR_CLI_DAEMON=true, set by the mix
  # release's daemon startup) starts the repo + Oban and stays alive.
  # Confirmed empirically that every run mode (Burrito release, `mix run`)
  # boots this whole application on every invocation - without this gate,
  # every interactive command would also open a database connection and
  # boot Oban's full supervision tree. See documents/phase-7-plan.adoc.
  #
  # Which repo/engine actually starts is resolved fresh on every boot via
  # LinearCli.ObanRepo.{repo,oban_engine}/0, not baked in at compile time -
  # see that module's moduledoc for why this has to be a runtime choice.
  defp start_daemon do
    repo = LinearCli.ObanRepo.repo()
    ensure_db_ready!(repo)

    oban_opts =
      :linear_cli
      |> Application.fetch_env!(Oban)
      |> Keyword.merge(repo: repo, engine: LinearCli.ObanRepo.oban_engine())

    opts = [strategy: :one_for_one, name: LinearCli.Supervisor]
    Supervisor.start_link([repo, {Oban, oban_opts}], opts)
  end

  # A Burrito-wrapped release boots via `-s elixir start_cli`, which only
  # recognizes Elixir's own CLI flags (`--help`/`--version`) and otherwise
  # tries to run the first arg as a script file (see
  # documents/phase-8-plan.adoc's Burrito verification - it only exercised
  # the daemon boot-and-stay-alive path, not this one). `LinearCli.CLI.
  # main/2` never reaches this call site as a Burrito release, so it has
  # to happen here instead, per Burrito's own "Application Entry Point"
  # README section. `running_standalone?/0` (checks the `__BURRITO` env
  # var the Zig wrapper sets) is what distinguishes that case from `mix
  # run`, where the caller (a test, an `-e` script, IEx) invokes
  # `LinearCli.CLI.main/1` itself - calling it again here would run every
  # interactive command twice.
  defp start_interactive do
    if Burrito.Util.running_standalone?() do
      LinearCli.CLI.main(Burrito.Util.Args.argv())
      System.halt(0)
    end

    opts = [strategy: :one_for_one, name: LinearCli.Supervisor]
    Supervisor.start_link([], opts)
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
