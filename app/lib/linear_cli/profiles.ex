defmodule LinearCli.Profiles do
  @moduledoc """
  Named team/project bundles ("profiles"), persisted in a small local
  SQLite file (`~/.linear_cli/profiles.db` in prod - see
  `config/runtime.exs`'s `:profiles_db_path`), with at most one active at a
  time - enforced by a partial unique index (`active_idx`), not
  application-level bookkeeping. `default_team/0`/`default_project/0` are
  what `LinearCli.CLI.IssueHelpers.make_da_issue!/1` and
  `LinearCli.CLI.Commands.issue_list/1` fall back to when `--team`/
  `--project` are omitted - see `documents/phase-9-plan.adoc`.

  New in this port - Ruby has no equivalent. Uses `Exqlite.Sqlite3`
  directly rather than a new `Ecto.Repo`: `LinearCli.Application`'s
  interactive-mode supervisor is deliberately empty (see its own
  comments), and adding a pooled repo plus migration ceremony there for a
  four-column table is exactly the overhead that emptiness exists to
  avoid. Every function here opens its own connection, ensures the
  schema, and closes - no long-lived process, nothing to migrate ahead of
  time.
  """

  defmodule Profile do
    @moduledoc "A saved team/project bundle - see `LinearCli.Profiles`."
    defstruct [:id, :name, :team, :project, :active]
  end

  alias Exqlite.Sqlite3

  @doc "Saves a new profile. `opts`: optional `:team`/`:project` search terms."
  @spec create(String.t(), keyword()) :: {:ok, %Profile{}} | {:error, term()}
  def create(name, opts \\ []) do
    team = opts[:team]
    project = opts[:project]

    with_db(fn conn ->
      case exec(conn, "INSERT INTO profiles (name, team, project) VALUES (?, ?, ?)", [
             name,
             team,
             project
           ]) do
        :ok ->
          {:ok, id} = Sqlite3.last_insert_rowid(conn)
          {:ok, %Profile{id: id, name: name, team: team, project: project, active: false}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc "All saved profiles, ordered by name."
  @spec list() :: [%Profile{}]
  def list do
    with_db(fn conn ->
      conn
      |> query("SELECT id, name, team, project, active FROM profiles ORDER BY name")
      |> Enum.map(&row_to_profile/1)
    end)
  end

  @doc "Switches the active profile to `name`. `{:error, :not_found}` if no such profile exists."
  @spec activate(String.t()) :: :ok | {:error, :not_found}
  def activate(name) do
    with_db(fn conn ->
      :ok = exec(conn, "UPDATE profiles SET active = 0", [])
      :ok = exec(conn, "UPDATE profiles SET active = 1 WHERE name = ?", [name])
      changed?(conn)
    end)
  end

  @doc "The single active profile, or `nil`."
  @spec active() :: %Profile{} | nil
  def active do
    with_db(fn conn ->
      case query(conn, "SELECT id, name, team, project, active FROM profiles WHERE active = 1") do
        [row] -> row_to_profile(row)
        [] -> nil
      end
    end)
  end

  @doc "Deletes the named profile. `{:error, :not_found}` if no such profile exists."
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(name) do
    with_db(fn conn ->
      :ok = exec(conn, "DELETE FROM profiles WHERE name = ?", [name])
      changed?(conn)
    end)
  end

  @doc "The active profile's team, or `nil` with no active profile."
  @spec default_team() :: String.t() | nil
  def default_team, do: active_field(:team)

  @doc "The active profile's project, or `nil` with no active profile."
  @spec default_project() :: String.t() | nil
  def default_project, do: active_field(:project)

  defp active_field(field) do
    case active() do
      nil -> nil
      profile -> Map.get(profile, field)
    end
  end

  defp changed?(conn) do
    case Sqlite3.changes(conn) do
      {:ok, 0} -> {:error, :not_found}
      {:ok, _changed} -> :ok
    end
  end

  defp row_to_profile([id, name, team, project, active]) do
    %Profile{id: id, name: name, team: team, project: project, active: active == 1}
  end

  defp with_db(fun) do
    path = db_path()
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Sqlite3.open(path)

    try do
      ensure_schema!(conn)
      fun.(conn)
    after
      Sqlite3.close(conn)
    end
  end

  defp ensure_schema!(conn) do
    :ok =
      exec(
        conn,
        """
        CREATE TABLE IF NOT EXISTS profiles (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          team TEXT,
          project TEXT,
          active INTEGER NOT NULL DEFAULT 0
        )
        """,
        []
      )

    :ok =
      exec(
        conn,
        "CREATE UNIQUE INDEX IF NOT EXISTS profiles_active_idx ON profiles(active) WHERE active = 1",
        []
      )
  end

  defp exec(conn, sql, []), do: Sqlite3.execute(conn, sql)

  defp exec(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, params),
         :done <- Sqlite3.step(conn, stmt) do
      :ok
    end
  end

  defp query(conn, sql) do
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
    rows
  end

  defp db_path, do: Application.fetch_env!(:linear_cli, :profiles_db_path)
end
