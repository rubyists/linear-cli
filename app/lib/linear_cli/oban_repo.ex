defmodule LinearCli.ObanRepo do
  @moduledoc """
  Resolves which Ecto repo (and matching Oban engine) actually backs Oban's
  job table, at *runtime* - `LINEAR_CLI_DB_ADAPTER=sqlite|postgres` (default
  `sqlite`), read fresh every time the daemon boots (see
  `LinearCli.Application`). This is what lets one compiled escript/release
  run against either backend on whatever machine it's deployed to, with no
  rebuild.

  The *adapter* itself is still necessarily fixed per `Ecto.Repo` module -
  `Ecto.Repo.Supervisor.compile_config/2` reads `:adapter` from `use
  Ecto.Repo`'s own compile-time opts, never from `Application` config, so a
  single repo module can't switch drivers at runtime. The fix is this
  module, not a compile-time flag on one repo: both
  `LinearCli.ObanRepo.Sqlite` and `LinearCli.ObanRepo.Postgres` are always
  compiled in (both `ecto_sqlite3` and `postgrex` are unconditional deps),
  and this module just picks which one `LinearCli.Application` actually
  starts.

  Connection details for both repos live in `config/runtime.exs`, resolved
  at boot too, so a daemon restart - not a rebuild - also picks up new
  credentials/host.
  """

  @doc "The Ecto repo module to start for this run - see LinearCli.Application."
  def repo, do: adapter() |> repo_for()

  @doc "Oban's data-layer engine matching `repo/0`."
  def oban_engine, do: adapter() |> engine_for()

  defp adapter do
    case System.get_env("LINEAR_CLI_DB_ADAPTER", "sqlite") do
      valid when valid in ["sqlite", "postgres"] ->
        valid

      other ->
        raise "LINEAR_CLI_DB_ADAPTER must be \"sqlite\" or \"postgres\", got: #{inspect(other)}"
    end
  end

  defp repo_for("sqlite"), do: LinearCli.ObanRepo.Sqlite
  defp repo_for("postgres"), do: LinearCli.ObanRepo.Postgres

  defp engine_for("sqlite"), do: Oban.Engines.Lite
  defp engine_for("postgres"), do: Oban.Engines.Basic
end
