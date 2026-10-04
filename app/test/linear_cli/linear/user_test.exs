defmodule LinearCli.Linear.UserTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "team_members/1 returns a list of users for a valid team response" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "members" => %{
              "edges" => [
                %{
                  "node" => %{"id" => "u1", "name" => "Alice", "email" => "alice@example.com"},
                  "cursor" => "member-1"
                },
                %{
                  "node" => %{"id" => "u2", "name" => "Bob", "email" => "bob@example.com"},
                  "cursor" => "member-2"
                }
              ],
              "pageInfo" => %{"hasNextPage" => false, "endCursor" => "member-2"}
            }
          }
        }
      })
    end)

    assert {:ok, [%Linear.User{id: "u1", name: "Alice"}, %Linear.User{id: "u2", name: "Bob"}]} =
             Linear.team_members("t1")
  end

  test "team_members/1 follows every member page" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      query = decoded["query"]
      after_cursor = decoded["variables"]["after"]

      assert query =~ "members(first: 50, after: $after)"

      {members, page_info} =
        case after_cursor do
          nil ->
            {[%{"id" => "u1", "name" => "First", "email" => "first@example.com"}],
             %{"hasNextPage" => true, "endCursor" => "member-1"}}

          "member-1" ->
            {[%{"id" => "u2", "name" => "Later", "email" => "later@example.com"}],
             %{"hasNextPage" => false, "endCursor" => "member-2"}}
        end

      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "members" => %{
              "edges" => Enum.map(members, &%{"node" => &1, "cursor" => &1["id"]}),
              "pageInfo" => page_info
            }
          }
        }
      })
    end)

    assert {:ok, members} = Linear.team_members("t1")
    assert Enum.map(members, & &1.id) == ["u1", "u2"]
  end

  test "team_members/1 returns an empty list when team is null" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"team" => nil}})
    end)

    assert {:ok, []} = Linear.team_members("nonexistent")
  end

  test "team_members/1 returns an empty list when members key is absent" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"team" => %{}}})
    end)

    assert {:ok, []} = Linear.team_members("t1")
  end

  test "team_members/1 returns an empty list when nodes key is absent" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"team" => %{"members" => %{}}}})
    end)

    assert {:ok, []} = Linear.team_members("t1")
  end

  test "workspace_team_members/1 follows every member page for lookup" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      query = decoded["query"]
      after_cursor = decoded["variables"]["after"]
      assert query =~ "members(first: 50, after: $after)"

      {members, page_info} =
        case after_cursor do
          nil ->
            {[%{"id" => "u1", "name" => "First", "email" => "first@example.com"}],
             %{"hasNextPage" => true, "endCursor" => "member-1"}}

          "member-1" ->
            {[%{"id" => "u2", "name" => "Later", "email" => "later@example.com"}],
             %{"hasNextPage" => false, "endCursor" => "member-2"}}
        end

      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "members" => %{
              "edges" => Enum.map(members, &%{"node" => &1, "cursor" => &1["id"]}),
              "pageInfo" => page_info
            }
          }
        }
      })
    end)

    assert {:ok, members} = Linear.workspace_team_members("t1")
    assert Enum.map(members, & &1.id) == ["u1", "u2"]
  end

  test "workspace_team_members/1 reports a malformed later page" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      after_cursor = Jason.decode!(body)["variables"]["after"]

      response =
        case after_cursor do
          nil ->
            %{
              "data" => %{
                "team" => %{
                  "members" => %{
                    "edges" => [],
                    "pageInfo" => %{"hasNextPage" => true, "endCursor" => "member-1"}
                  }
                }
              }
            }

          "member-1" ->
            %{"data" => %{"team" => nil}}
        end

      Req.Test.json(conn, response)
    end)

    assert {:error, %Ash.Error.Unknown{errors: [%{value: [{:unexpected_response, _}]}]}} =
             Linear.workspace_team_members("t1")
  end

  test "team_members/1 propagates API errors" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"errors" => [%{"message" => "Unauthorized"}]})
    end)

    assert {:error, %Ash.Error.Unknown{}} = Linear.team_members("t1")
  end

  test "team_members/1 normalizes HTTP errors" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Plug.Conn.resp(conn, 401, "upstream unavailable")
    end)

    assert {:error, %Ash.Error.Unknown{errors: [%{value: [{:http_error, 401}]} | _]}} =
             Linear.team_members("t1")
  end

  test "me/0 returns an unexpected_response error when viewer is null" do
    # Linear returns {"data": {"viewer": null}} when the API key is valid but
    # refers to an account that no longer exists. Guard `when is_map(viewer)`
    # prevents User.from_map(nil) from crashing.
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"viewer" => nil}})
    end)

    assert {:error, %Ash.Error.Unknown{errors: [%{value: [{:unexpected_response, _}]}]}} =
             Linear.me()
  end

  test "me/0 returns an unexpected_response error when viewer key is absent" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{}})
    end)

    assert {:error, %Ash.Error.Unknown{errors: [%{value: [{:unexpected_response, _}]}]}} =
             Linear.me()
  end

  test "me/0 decodes the viewer, including nested teams" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "viewer" => %{
            "id" => "u1",
            "name" => "Ada Lovelace",
            "email" => "ada@example.com",
            "teams" => %{
              "nodes" => [
                %{
                  "id" => "t1",
                  "key" => "ENG",
                  "name" => "Engineering",
                  "description" => nil
                }
              ]
            }
          }
        }
      })
    end)

    assert {:ok, user} = Linear.me()
    assert user.id == "u1"
    assert user.name == "Ada Lovelace"
    assert user.email == "ada@example.com"
    assert [%Linear.Team{id: "t1", key: "ENG", name: "Engineering"}] = user.teams
  end
end
