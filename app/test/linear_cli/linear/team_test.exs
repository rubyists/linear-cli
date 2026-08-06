defmodule LinearCli.Linear.TeamTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "my_teams/0 delegates to the viewer's teams (Ruby: Team.mine = User.me.teams)" do
    Req.Test.stub(LinearCli.Api, fn conn ->
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
    end)

    assert {:ok, [%Linear.Team{id: "t1", key: "ENG"}]} = Linear.my_teams()
  end

  test "teams/0 pages through the full team list (Ruby: BaseModel::ClassMethods#all)" do
    team_node = fn id -> %{"id" => id, "key" => id, "name" => id, "description" => nil} end

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => %{"after" => after_cursor}} = Jason.decode!(body)

      case after_cursor do
        nil ->
          Req.Test.json(conn, %{
            "data" => %{
              "teams" => %{
                "edges" => [%{"node" => team_node.("t1"), "cursor" => "c1"}],
                "pageInfo" => %{"hasNextPage" => true, "endCursor" => "c1"}
              }
            }
          })

        "c1" ->
          Req.Test.json(conn, %{
            "data" => %{
              "teams" => %{
                "edges" => [%{"node" => team_node.("t2"), "cursor" => "c2"}],
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => "c2"}
              }
            }
          })
      end
    end)

    assert {:ok, [%Linear.Team{id: "t1"}, %Linear.Team{id: "t2"}]} = Linear.teams()
  end

  test "find_team/1 looks up a single team by id (Ruby: BaseModel::ClassMethods#find)" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query, "variables" => %{"id" => id}} = Jason.decode!(body)

      assert id == "ENG"
      assert query =~ "team(id: $id)"

      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "id" => "t1",
            "key" => "ENG",
            "name" => "Engineering",
            "description" => nil
          }
        }
      })
    end)

    assert {:ok, %Linear.Team{id: "t1", key: "ENG"}} = Linear.find_team("ENG")
  end

  test "find_team/1 surfaces a not-found error when the API returns a nil team" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"team" => nil}})
    end)

    assert {:error, _not_found} = Linear.find_team("nope")
  end
end
