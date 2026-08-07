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

  describe "create_project/2+ (new in Phase 7 - no Ruby equivalent)" do
    test "sends name/teamIds and returns the created project via base_fields" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"input" => input}} = Jason.decode!(body)

        assert input == %{"name" => "August 2026", "teamIds" => ["t1"]}

        Req.Test.json(conn, %{
          "data" => %{
            "projectCreate" => %{
              "project" => %{
                "id" => "p9",
                "name" => "August 2026",
                "content" => nil,
                "slugId" => "abc123",
                "description" => "",
                "url" => "https://linear.app/x/project/august-2026-abc123"
              },
              "success" => true,
              "lastSyncId" => 1.0
            }
          }
        })
      end)

      assert {:ok, project} = Linear.create_project("August 2026", "t1")
      assert project.id == "p9"
      assert project.name == "August 2026"
    end
  end

  describe "find_project_by_name/1 (new in Phase 7 - no Ruby equivalent)" do
    test "returns the matching project with its teams" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"name" => "PAYMENTS SWAT August 2026"}} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "projects" => %{
              "nodes" => [
                %{
                  "id" => "p1",
                  "name" => "PAYMENTS SWAT August 2026",
                  "content" => nil,
                  "slugId" => "abc123",
                  "description" => "",
                  "url" => "https://linear.app/x/project/aug26-abc123",
                  "teams" => %{
                    "nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]
                  }
                }
              ]
            }
          }
        })
      end)

      assert {:ok, project} = Linear.find_project_by_name("PAYMENTS SWAT August 2026")
      assert project.id == "p1"
      assert [%Linear.Team{id: "t1"}] = project.teams
    end

    test "returns a not-found error when no project matches" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"data" => %{"projects" => %{"nodes" => []}}})
      end)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Linear.find_project_by_name("nope")
    end
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
