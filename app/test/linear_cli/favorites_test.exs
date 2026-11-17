defmodule LinearCli.FavoritesTest do
  # Not async: shares the one sqlite file at `config :linear_cli,
  # :profiles_db_path` with LinearCli.ProfilesTest - `setup` below deletes
  # it fresh before each test instead.
  use ExUnit.Case, async: false

  alias LinearCli.Favorites

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)
    :ok
  end

  describe "add/2 and list/1" do
    test "favorites a value under a kind and lists it back" do
      :ok = Favorites.add("team", "CRY")
      assert Favorites.list("team") == ["CRY"]
    end

    test "kinds are independent" do
      :ok = Favorites.add("team", "CRY")
      :ok = Favorites.add("project", "p1")

      assert Favorites.list("team") == ["CRY"]
      assert Favorites.list("project") == ["p1"]
    end

    test "favoriting the same value twice is a no-op, not an error" do
      :ok = Favorites.add("team", "CRY")
      :ok = Favorites.add("team", "CRY")
      assert Favorites.list("team") == ["CRY"]
    end

    test "lists multiple favorites ordered by value" do
      :ok = Favorites.add("team", "ENG")
      :ok = Favorites.add("team", "CRY")

      assert Favorites.list("team") == ["CRY", "ENG"]
    end

    test "an unknown kind has no favorites" do
      assert Favorites.list("nope") == []
    end
  end

  describe "remove/2" do
    test "un-favorites a value" do
      :ok = Favorites.add("team", "CRY")
      :ok = Favorites.remove("team", "CRY")
      assert Favorites.list("team") == []
    end

    test "removing a value that was never favorited is a no-op" do
      assert :ok = Favorites.remove("team", "nope")
    end
  end

  test "details survive repeated adds and can be refreshed" do
    :ok = Favorites.add("project", "p1", %{"name" => "Wallet Service Extraction"})
    :ok = Favorites.add("project", "p1")

    assert [%{value: "p1", details: %{"name" => "Wallet Service Extraction"}}] =
             Favorites.entries("project")

    :ok = Favorites.add("project", "p1", %{"name" => "Renamed"})
    assert [%{value: "p1", details: %{"name" => "Renamed"}}] = Favorites.entries("project")
  end

  test "upgrades an identifier-only database without losing favorites" do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE favorites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        value TEXT NOT NULL,
        UNIQUE(kind, value)
      );
      INSERT INTO favorites (kind, value) VALUES ('project', 'p1');
      """)

    :ok = Exqlite.Sqlite3.close(conn)

    assert [%{value: "p1", details: nil}] = Favorites.entries("project")
    :ok = Favorites.add("project", "p1", %{"name" => "Wallet Service Extraction"})
    assert Favorites.list("project") == ["p1"]
    assert [%{details: %{"name" => "Wallet Service Extraction"}}] = Favorites.entries("project")
  end
end
