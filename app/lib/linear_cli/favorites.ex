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

  `list/1` returns identifiers for default resolution. `entries/1` also
  returns saved display details, allowing list commands to work offline.
  Older identifier-only entries have nil details until hydrated once.

  New in this port - Ruby has no equivalent.
  """

  alias Exqlite.Sqlite3
  alias LinearCli.Linear

  @doc """
  Favorites `value` under `kind` (`"team"` or `"project"`). Supplying
  details refreshes the saved snapshot; omitting them preserves existing details.
  """
  @spec add(String.t(), String.t(), map() | nil) :: :ok
  def add(kind, value, details \\ nil) do
    with_db(fn conn ->
      exec(
        conn,
        """
        INSERT INTO favorites (kind, value, details) VALUES (?, ?, ?)
        ON CONFLICT(kind, value) DO UPDATE SET details = COALESCE(excluded.details, favorites.details)
        """,
        [kind, value, if(details, do: Jason.encode!(details))]
      )
    end)
  end

  @doc "Saved favorites and their JSON display details, ordered by value."
  @spec entries(String.t()) :: [%{value: String.t(), details: map() | nil}]
  def entries(kind) do
    with_db(fn conn ->
      conn
      |> query("SELECT value, details FROM favorites WHERE kind = ? ORDER BY value", [kind])
      |> Enum.map(fn [value, details] ->
        %{value: value, details: if(details, do: Jason.decode!(details))}
      end)
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

  def records(_kind, true), do: {:ok, nil}

  def records(kind, _all?) do
    case entries(kind) do
      [] ->
        {:ok, nil}

      entries ->
        Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, records} ->
          case favorite_record(kind, entry) do
            {:ok, record} -> {:cont, {:ok, [record | records]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, records} -> {:ok, Enum.reverse(records)}
          error -> error
        end
    end
  end

  # Older databases have only identifiers. Resolve each missing snapshot
  # directly once, without fetching a workspace-wide list.
  defp favorite_record(kind, %{value: value, details: nil}) do
    result = if kind == "team", do: Linear.find_team(value), else: Linear.find_project(value)

    with {:ok, record} <- result do
      :ok = save(kind, record)
      {:ok, record}
    end
  end

  defp favorite_record("team", %{details: details}), do: {:ok, Linear.Team.from_map(details)}

  defp favorite_record("project", %{details: details}),
    do: {:ok, Linear.Project.from_map(details)}

  def save("team", team) do
    add("team", team.key, team_details(team))
  end

  def save("project", project) do
    details = %{
      "id" => project.id,
      "name" => project.name,
      "url" => project.url,
      "slugId" => project.slug_id,
      "description" => project.description,
      "content" => project.content,
      "teams" => %{"nodes" => Enum.map(project.teams, &team_details/1)}
    }

    add("project", project.id, details)
  end

  defp team_details(team), do: Map.take(team, [:id, :key, :name, :description])

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
          details TEXT,
          UNIQUE(kind, value)
        )
        """,
        []
      )

    unless Enum.any?(query(conn, "PRAGMA table_info(favorites)", []), fn row ->
             Enum.at(row, 1) == "details"
           end) do
      :ok = exec(conn, "ALTER TABLE favorites ADD COLUMN details TEXT", [])
    end
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
