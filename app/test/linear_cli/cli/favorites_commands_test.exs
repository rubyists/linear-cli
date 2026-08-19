defmodule LinearCli.CLI.FavoritesCommandsTest do
  # Not async: shares LinearCli.Profiles/LinearCli.Favorites' one sqlite
  # file (config :linear_cli, :profiles_db_path) - `setup` below deletes
  # it fresh before each test instead.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)
      respond(conn, query)
    end)

    :ok
  end

  defp respond(conn, query) do
    cond do
      query =~ "team(id: $id)" ->
        Req.Test.json(conn, %{
          "data" => %{"team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}}
        })

      query =~ "teams(" ->
        Req.Test.json(conn, %{
          "data" => %{
            "teams" => %{
              "edges" => [
                %{
                  "node" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                  "cursor" => "c1"
                },
                %{"node" => %{"id" => "t2", "key" => "OPS", "name" => "Ops"}, "cursor" => "c2"}
              ],
              "pageInfo" => %{"hasNextPage" => false}
            }
          }
        })

      query =~ "viewer" ->
        Req.Test.json(conn, %{
          "data" => %{
            "viewer" => %{
              "id" => "u1",
              "name" => "Ada",
              "email" => "ada@example.com",
              "teams" => %{"nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]}
            }
          }
        })

      query =~ "team(id: $teamId)" ->
        Req.Test.json(conn, %{
          "data" => %{
            "team" => %{
              "projects" => %{
                "nodes" => [
                  %{
                    "id" => "p1",
                    "name" => "Manhattan",
                    "slugId" => "abc",
                    "url" => "https://linear.app/x/project/manhattan-abc"
                  },
                  %{
                    "id" => "p2",
                    "name" => "Platform Cleanup",
                    "slugId" => "def",
                    "url" => "https://linear.app/x/project/platform-cleanup-def"
                  }
                ]
              }
            }
          }
        })

      query =~ "projects(" ->
        Req.Test.json(conn, %{
          "data" => %{
            "projects" => %{
              "edges" => [
                %{
                  "node" => %{
                    "id" => "p1",
                    "name" => "Manhattan",
                    "slugId" => "abc",
                    "url" => "https://linear.app/x/project/manhattan-abc"
                  },
                  "cursor" => "c1"
                },
                %{
                  "node" => %{
                    "id" => "p2",
                    "name" => "Platform Cleanup",
                    "slugId" => "def",
                    "url" => "https://linear.app/x/project/platform-cleanup-def"
                  },
                  "cursor" => "c2"
                }
              ],
              "pageInfo" => %{"hasNextPage" => false}
            }
          }
        })
    end
  end

  describe "team favorite/unfavorite" do
    test "favorites a team by key" do
      assert capture_io(fn -> assert :ok = LinearCli.CLI.main(["team", "favorite", "ENG"]) end) =~
               "Favorited team ENG"

      assert LinearCli.Favorites.list("team") == ["ENG"]
    end

    test "un-favorites a team by key" do
      LinearCli.Favorites.add("team", "ENG")

      assert capture_io(fn -> assert :ok = LinearCli.CLI.main(["team", "unfavorite", "ENG"]) end) =~
               "Un-favorited team ENG"

      assert LinearCli.Favorites.list("team") == []
    end
  end

  describe "project favorite/unfavorite" do
    test "resolves the project by name and favorites its id" do
      assert capture_io(fn ->
               assert :ok = LinearCli.CLI.main(["project", "favorite", "Manhattan"])
             end) =~ "Favorited project Manhattan"

      assert LinearCli.Favorites.list("project") == ["p1"]
    end

    test "un-favorites a project by name" do
      LinearCli.Favorites.add("project", "p1")

      assert capture_io(fn ->
               assert :ok = LinearCli.CLI.main(["project", "unfavorite", "Manhattan"])
             end) =~ "Un-favorited project Manhattan"

      assert LinearCli.Favorites.list("project") == []
    end
  end

  describe "team list favorites filtering" do
    test "with no favorites, --no-mine still lists every team unchanged" do
      output = capture_io(fn -> LinearCli.CLI.main(["team", "list", "--no-mine"]) end)
      assert output =~ "Engineering"
      assert output =~ "Ops"
    end

    test "once a team is favorited, --no-mine only shows favorites" do
      LinearCli.Favorites.add("team", "OPS")

      output = capture_io(fn -> LinearCli.CLI.main(["team", "list", "--no-mine"]) end)
      assert output =~ "Ops"
      refute output =~ "Engineering"
    end

    test "--all overrides the favorites filter" do
      LinearCli.Favorites.add("team", "OPS")

      output = capture_io(fn -> LinearCli.CLI.main(["team", "list", "--no-mine", "--all"]) end)
      assert output =~ "Ops"
      assert output =~ "Engineering"
    end
  end

  describe "project list favorites filtering" do
    test "with no favorites, lists every project unchanged" do
      output = capture_io(fn -> LinearCli.CLI.main(["project", "list"]) end)
      assert output =~ "Manhattan"
      assert output =~ "Platform Cleanup"
    end

    test "once a project is favorited, only it is shown" do
      LinearCli.Favorites.add("project", "p1")

      output = capture_io(fn -> LinearCli.CLI.main(["project", "list"]) end)
      assert output =~ "Manhattan"
      refute output =~ "Platform Cleanup"
    end

    test "--all overrides the favorites filter" do
      LinearCli.Favorites.add("project", "p1")

      output = capture_io(fn -> LinearCli.CLI.main(["project", "list", "--all"]) end)
      assert output =~ "Manhattan"
      assert output =~ "Platform Cleanup"
    end
  end
end
