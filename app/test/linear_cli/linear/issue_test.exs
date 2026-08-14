defmodule LinearCli.Linear.IssueTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "issues/0 defaults to the caller's own open issues (Ruby: filter[:assignee] = isMe)" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => %{"filter" => filter}} = Jason.decode!(body)

      assert filter == %{
               "completedAt" => %{"null" => true},
               "canceledAt" => %{"null" => true},
               "assignee" => %{"isMe" => %{"eq" => true}}
             }

      Req.Test.json(conn, %{
        "data" => %{
          "issues" => %{
            "edges" => [
              %{
                "node" => %{
                  "id" => "i1",
                  "identifier" => "CRY-1",
                  "title" => "Fix the thing",
                  "branchName" => "cry-1-fix-the-thing",
                  "description" => nil,
                  "assignee" => %{
                    "id" => "u1",
                    "name" => "Ada",
                    "email" => "ada@example.com",
                    "teams" => %{"nodes" => []}
                  },
                  "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
                },
                "cursor" => "c1"
              }
            ],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => "c1"}
          }
        }
      })
    end)

    assert {:ok, [issue]} = Linear.issues()
    assert issue.identifier == "CRY-1"
    assert issue.assignee.name == "Ada"
    assert issue.team.key == "ENG"
  end

  test "issues/1 with unassigned: true overrides mine, even when mine defaults true" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => %{"filter" => filter}} = Jason.decode!(body)
      assert filter["assignee"] == %{"null" => true}

      Req.Test.json(conn, %{
        "data" => %{"issues" => %{"edges" => [], "pageInfo" => %{"hasNextPage" => false}}}
      })
    end)

    assert {:ok, []} = Linear.issues(%{unassigned: true})
  end

  test "issues/1 with ids fetches each by id via the full-detail query" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query, "variables" => %{"id" => id}} = Jason.decode!(body)

      assert id == "CRY-2"
      assert query =~ "issue(id: $id)"
      assert query =~ "comments"

      Req.Test.json(conn, %{
        "data" => %{
          "issue" => %{
            "id" => "i2",
            "identifier" => "CRY-2",
            "title" => "Ship it",
            "branchName" => "cry-2-ship-it",
            "description" => nil,
            "assignee" => nil,
            "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
            "comments" => %{"nodes" => []}
          }
        }
      })
    end)

    assert {:ok, [issue]} = Linear.issues(%{ids: ["cry-2"]})
    assert issue.identifier == "CRY-2"
  end

  test "issues/1 parses the issue's current state when present in the response" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)
      assert query =~ "state {"

      Req.Test.json(conn, %{
        "data" => %{
          "issue" => %{
            "id" => "i2",
            "identifier" => "CRY-2",
            "title" => "Ship it",
            "branchName" => "cry-2-ship-it",
            "description" => nil,
            "assignee" => nil,
            "state" => %{"id" => "s1", "name" => "Done", "type" => "completed"},
            "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
            "comments" => %{"nodes" => []}
          }
        }
      })
    end)

    assert {:ok, [issue]} = Linear.issues(%{ids: ["cry-2"]})
    assert issue.state.type == "completed"
    assert issue.state.name == "Done"
  end

  test "issues/1 with an unknown id returns a not_found error" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"issue" => nil}})
    end)

    # Ash wraps the manual action's {:error, {:not_found, id}} into a generic
    # %Ash.Error.Unknown{} with no human-readable message yet - turning that
    # into something a CLI user should actually see is Phase 4's job (the
    # planned "central rescue -> exit-code mapping"). For now, just confirm a
    # bad id errors rather than silently succeeding.
    assert {:error, %Ash.Error.Unknown{}} = Linear.issues(%{ids: ["nope"]})
  end

  describe "create_issue/3+" do
    test "sends title/description/teamId and returns the created issue via base_fields" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"input" => input}} = Jason.decode!(body)

        assert input == %{"title" => "Fix it", "description" => "Details", "teamId" => "t1"}

        Req.Test.json(conn, %{
          "data" => %{
            "issueCreate" => %{
              "issue" => %{
                "id" => "i9",
                "identifier" => "CRY-9",
                "title" => "Fix it",
                "branchName" => "cry-9-fix-it",
                "description" => "Details",
                "assignee" => nil,
                "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
              }
            }
          }
        })
      end)

      assert {:ok, issue} = Linear.create_issue("Fix it", "Details", "t1")
      assert issue.identifier == "CRY-9"
      assert issue.team.key == "ENG"
    end

    test "includes labelIds only when non-empty and projectId only when given" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"input" => input}} = Jason.decode!(body)

        assert input == %{
                 "title" => "Fix it",
                 "description" => nil,
                 "teamId" => "t1",
                 "labelIds" => ["l1", "l2"],
                 "projectId" => "p1"
               }

        Req.Test.json(conn, %{
          "data" => %{
            "issueCreate" => %{
              "issue" => %{
                "id" => "i9",
                "identifier" => "CRY-9",
                "title" => "Fix it",
                "branchName" => "cry-9-fix-it",
                "description" => nil,
                "assignee" => nil,
                "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
              }
            }
          }
        })
      end)

      assert {:ok, _issue} =
               Linear.create_issue("Fix it", nil, "t1", %{
                 project_id: "p1",
                 label_ids: ["l1", "l2"]
               })
    end

    test "surfaces a GraphQL error" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "bad input"}]})
      end)

      assert {:error, %Ash.Error.Unknown{}} = Linear.create_issue("Fix it", "Details", "t1")
    end
  end

  describe "assign_issue/2+" do
    test "sends assigneeId and returns the issue refetched via full_fields" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"id" => id, "input" => input}} = Jason.decode!(body)

        assert id == "CRY-1"
        assert input == %{"assigneeId" => "u2"}

        Req.Test.json(conn, %{
          "data" => %{
            "issueUpdate" => %{
              "issue" => %{
                "id" => "i1",
                "identifier" => "CRY-1",
                "title" => "Fix it",
                "branchName" => "cry-1-fix-it",
                "description" => nil,
                "assignee" => %{
                  "id" => "u2",
                  "name" => "Bea",
                  "email" => "bea@example.com",
                  "teams" => %{"nodes" => []}
                },
                "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                "comments" => %{"nodes" => []}
              }
            }
          }
        })
      end)

      assert {:ok, updated} = Linear.assign_issue(issue, "u2")
      assert updated.assignee.name == "Bea"
    end

    test "surfaces a GraphQL error" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "no such user"}]})
      end)

      assert {:error, %Ash.Error.Invalid{}} = Linear.assign_issue(issue, "nope")
    end
  end

  describe "attach_issue_to_project/2+" do
    test "sends projectId and returns the issue refetched via full_fields" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"id" => id, "input" => input}} = Jason.decode!(body)

        assert id == "CRY-1"
        assert input == %{"projectId" => "p1"}

        Req.Test.json(conn, %{
          "data" => %{
            "issueUpdate" => %{
              "issue" => %{
                "id" => "i1",
                "identifier" => "CRY-1",
                "title" => "Fix it",
                "branchName" => "cry-1-fix-it",
                "description" => nil,
                "assignee" => nil,
                "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                "comments" => %{"nodes" => []}
              }
            }
          }
        })
      end)

      assert {:ok, updated} = Linear.attach_issue_to_project(issue, "p1")
      assert updated.identifier == "CRY-1"
    end

    test "surfaces a GraphQL error" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "no such project"}]})
      end)

      assert {:error, %Ash.Error.Invalid{}} = Linear.attach_issue_to_project(issue, "nope")
    end
  end

  describe "close_issue/2+" do
    test "omits trashed from the mutation input when not given (Linear API rejects trashed: false)" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"id" => id, "input" => input}} = Jason.decode!(body)

        assert id == "CRY-1"
        assert input == %{"stateId" => "s1"}

        Req.Test.json(conn, %{
          "data" => %{
            "issueUpdate" => %{
              "issue" => %{
                "id" => "i1",
                "identifier" => "CRY-1",
                "title" => "Fix it",
                "branchName" => "cry-1-fix-it",
                "description" => nil,
                "assignee" => nil,
                "state" => %{"id" => "s1", "name" => "Done", "type" => "completed"},
                "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                "comments" => %{"nodes" => []}
              }
            }
          }
        })
      end)

      assert {:ok, updated} = Linear.close_issue(issue, "s1")
      assert updated.state.type == "completed"
      assert updated.state.name == "Done"
    end

    test "sends trashed: true when given via opts" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"input" => input}} = Jason.decode!(body)

        assert input == %{"stateId" => "s1", "trashed" => true}

        Req.Test.json(conn, %{
          "data" => %{
            "issueUpdate" => %{
              "issue" => %{
                "id" => "i1",
                "identifier" => "CRY-1",
                "title" => "Fix it",
                "branchName" => "cry-1-fix-it",
                "description" => nil,
                "assignee" => nil,
                "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                "comments" => %{"nodes" => []}
              }
            }
          }
        })
      end)

      assert {:ok, _updated} = Linear.close_issue(issue, "s1", %{trash: true})
    end

    test "surfaces a GraphQL error" do
      issue = struct!(LinearCli.Linear.Issue, id: "i1", identifier: "CRY-1")

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "no such state"}]})
      end)

      assert {:error, %Ash.Error.Invalid{}} = Linear.close_issue(issue, "nope")
    end
  end
end
