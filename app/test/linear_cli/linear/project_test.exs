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

  describe "slug/1 (Ruby: Project#slug)" do
    test "strips the trailing -slugId suffix from the URL's basename" do
      project = %Linear.Project{
        url: "https://linear.app/x/project/manhattan-abc123",
        slug_id: "abc123"
      }

      assert Linear.Project.slug(project) == "manhattan"
    end

    test "only strips the first occurrence, matching Ruby's String#sub" do
      project = %Linear.Project{
        url: "https://linear.app/x/project/abc123-abc123",
        slug_id: "abc123"
      }

      assert Linear.Project.slug(project) == "abc123"
    end
  end

  describe "match_score?/2 (Ruby: Project#match_score?)" do
    setup do
      {:ok,
       project: %Linear.Project{
         id: "p1",
         name: "Manhattan",
         url: "https://linear.app/x/project/manhattan-abc123",
         slug_id: "abc123",
         description: "The Manhattan project rollout."
       }}
    end

    test "scores 100 on an exact (case-insensitive) id match", %{project: project} do
      assert Linear.Project.match_score?(project, "P1") == 100
    end

    test "scores 100 on an exact (case-insensitive) url match", %{project: project} do
      assert Linear.Project.match_score?(project, String.upcase(project.url)) == 100
    end

    test "scores 100 when the slugified search term equals the slug", %{project: project} do
      assert Linear.Project.match_score?(project, "manhattan") == 100
    end

    test "a slugified search term that doesn't equal the slug scores 0, since the space breaks the name/slug substring checks too",
         %{project: project} do
      assert Linear.Project.match_score?(project, "Man Hattan") == 0
    end

    test "scores 100 on an exact (case-insensitive) name match", %{project: project} do
      assert Linear.Project.match_score?(project, "MANHATTAN") == 100
    end

    test "scores 75 when the name contains the search term", %{project: project} do
      assert Linear.Project.match_score?(project, "Manhat") == 75
    end

    test "scores 75 when the slug contains the downcased search term", %{project: project} do
      assert Linear.Project.match_score?(project, "anhatt") == 75
    end

    test "scores 50 when the description contains the search term", %{project: project} do
      assert Linear.Project.match_score?(project, "rollout") == 50
    end

    test "scores 0 when nothing matches", %{project: project} do
      assert Linear.Project.match_score?(project, "gotham") == 0
    end
  end
end
