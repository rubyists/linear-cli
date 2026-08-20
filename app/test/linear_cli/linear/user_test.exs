defmodule LinearCli.Linear.UserTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "team_members/1 returns a list of users for a valid team response" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "members" => %{
              "nodes" => [
                %{"id" => "u1", "name" => "Alice", "email" => "alice@example.com"},
                %{"id" => "u2", "name" => "Bob", "email" => "bob@example.com"}
              ]
            }
          }
        }
      })
    end)

    assert {:ok, [%Linear.User{id: "u1", name: "Alice"}, %Linear.User{id: "u2", name: "Bob"}]} =
             Linear.team_members("t1")
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

  test "team_members/1 propagates API errors" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"errors" => [%{"message" => "Unauthorized"}]})
    end)

    assert {:error, %Ash.Error.Unknown{}} = Linear.team_members("t1")
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
