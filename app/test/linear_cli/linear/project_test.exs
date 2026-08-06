defmodule LinearCli.Linear.ProjectTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "projects/0 fetches a page of all projects" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "projects" => %{
            "edges" => [
              %{
                "node" => %{
                  "id" => "p1",
                  "name" => "Manhattan",
                  "content" => nil,
                  "slugId" => "abc123",
                  "description" => "",
                  "url" => "https://linear.app/x/project/manhattan-abc123"
                },
                "cursor" => "c1"
              }
            ],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => "c1"}
          }
        }
      })
    end)

    assert {:ok, [%Linear.Project{id: "p1", name: "Manhattan"}]} = Linear.projects()
  end

  test "my_projects/0 flat-maps each of the viewer's teams' projects (Ruby: Project.mine)" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => variables} = Jason.decode!(body)

      case variables do
        %{"teamId" => "t1"} ->
          Req.Test.json(conn, %{
            "data" => %{
              "team" => %{
                "projects" => %{
                  "nodes" => [
                    %{
                      "id" => "p1",
                      "name" => "Manhattan",
                      "content" => nil,
                      "slugId" => "abc123",
                      "description" => "",
                      "url" => "https://linear.app/x/project/manhattan-abc123"
                    }
                  ]
                }
              }
            }
          })

        _ ->
          Req.Test.json(conn, %{
            "data" => %{
              "viewer" => %{
                "id" => "u1",
                "name" => "Ada",
                "email" => "ada@example.com",
                "teams" => %{
                  "nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]
                }
              }
            }
          })
      end
    end)

    assert {:ok, [%Linear.Project{id: "p1", name: "Manhattan"}]} = Linear.my_projects()
  end
end
