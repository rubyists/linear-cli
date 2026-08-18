defmodule LinearCli.Favorites do
  @moduledoc """
  Favorited teams/projects, persisted in the same local SQLite file
  `LinearCli.Profiles` uses (`:profiles_db_path` - see
  `config/runtime.exs`), in their own `favorites` table. Reuses
  `LinearCli.Profiles`'s exact pattern (raw `Exqlite.Sqlite3`, one
  connection open/ensure-schema/close per call, no `Ecto.Repo`) rather
  than sharing code with it - see `documents/phase-10-plan.adoc` for why
  this stays its own module against the same file instead of a change to
  `LinearCli.Profiles` itself.

  `list/1`, once non-empty for a given `kind`, is what
  `LinearCli.CLI.Commands.team_list/1`/`project_list/1` filter their
  results down to by default (a new `--all` flag opts back out).

  New in this port - Ruby has no equivalent.
  """

  alias Exqlite.Sqlite3

  @doc ~s[Favorites `value` under `kind` (`"team"` or `"project"`). A no-op if already favorited.]
  @spec add(String.t(), String.t()) :: :ok
  def add(kind, value) do
    with_db(fn conn ->
      exec(conn, "INSERT OR IGNORE INTO favorites (kind, value) VALUES (?, ?)", [kind, value])
    end)
  end

  @doc "Un-favorites `value` under `kind`. A no-op if it wasn't favorited."
  @spec remove(String.t(), String.t()) :: :ok
  def remove(kind, value) do
    with_db(fn conn ->
      exec(conn, "DELETE FROM favorites WHERE kind = ? AND value = ?", [kind, value])
    end)
  end

  @doc "Every favorited value under `kind`, ordered by value."
  @spec list(String.t()) :: [String.t()]
  def list(kind) do
    with_db(fn conn ->
      conn
      |> query("SELECT value FROM favorites WHERE kind = ? ORDER BY value", [kind])
      |> Enum.map(fn [value] -> value end)
    end)
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
        CREATE TABLE IF NOT EXISTS favorites (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          value TEXT NOT NULL,
          UNIQUE(kind, value)
        )
        """,
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

  defp query(conn, sql, params) do
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    :ok = Sqlite3.bind(stmt, params)
    {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
    rows
  end

  defp db_path, do: Application.fetch_env!(:linear_cli, :profiles_db_path)
end
