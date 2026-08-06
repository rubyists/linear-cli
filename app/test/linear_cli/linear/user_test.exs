defmodule LinearCli.Linear.UserTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

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
