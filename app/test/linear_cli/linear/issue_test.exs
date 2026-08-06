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
end
