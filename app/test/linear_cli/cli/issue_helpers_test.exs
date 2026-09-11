defmodule LinearCli.CLI.IssueHelpersTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.IssueHelpers
  alias LinearCli.Linear.{Issue, Team, User}

  defp issue(attrs \\ %{}) do
    struct!(
      %Issue{
        id: "i1",
        identifier: "CRY-1",
        title: "Fix the thing",
        description: "It is broken",
        team: %Team{id: "t1", key: "ENG", name: "Engineering"}
      },
      attrs
    )
  end

  defp stub_responses(pairs) do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)

      case Enum.find(pairs, fn {match, _resp} -> String.contains?(query, match) end) do
        {_match, response} -> Req.Test.json(conn, response)
        nil -> raise "no stub matched query: #{query}"
      end
    end)
  end

  defp issue_updated(overrides) do
    issue_map =
      Map.merge(
        %{
          "id" => "i1",
          "identifier" => "CRY-1",
          "title" => "Fix the thing",
          "branchName" => "cry-1-fix-the-thing",
          "description" => "It is broken",
          "assignee" => nil,
          "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
          "comments" => %{"nodes" => []}
        },
        overrides
      )

    %{"data" => %{"issueUpdate" => %{"issue" => issue_map}}}
  end

  defp team_projects(projects) do
    %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}
  end

  describe "make_da_issue!/1 (Ruby: CLI::Issue#make_da_issue!)" do
    test "creates the issue with resolved title/description/team/labels/project" do
      stub_responses([
        {"team(id: $id)",
         %{
           "data" => %{
             "team" => %{
               "id" => "t1",
               "key" => "ENG",
               "name" => "Engineering",
               "description" => nil
             }
           }
         }},
        {"issueLabels",
         %{
           "data" => %{
             "issueLabels" => %{
               "edges" => [
                 %{
                   "node" => %{
                     "id" => "l1",
                     "name" => "urgent",
                     "description" => nil,
                     "isGroup" => false
                   }
                 }
               ]
             }
           }
         }},
        {"projects(first: 100",
         team_projects([
           %{
             "id" => "p1",
             "name" => "Manhattan Rollout",
             "content" => nil,
             "slugId" => "abc",
             "description" => nil,
             "url" => "https://linear.app/x/project/manhattan-rollout-abc"
           }
         ])},
        {"issueCreate",
         %{
           "data" => %{
             "issueCreate" => %{
               "issue" => %{
                 "id" => "i2",
                 "identifier" => "CRY-2",
                 "title" => "New thing",
                 "branchName" => "cry-2-new-thing",
                 "description" => "Some description",
                 "assignee" => nil,
                 "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
               }
             }
           }
         }}
      ])

      assert capture_io(fn ->
               assert {:ok, %Issue{identifier: "CRY-2"}} =
                        IssueHelpers.make_da_issue!(
                          title: "New thing",
                          description: "Some description",
                          team: "ENG",
                          labels: ["urgent"],
                          project: "Manhattan Rollout"
                        )
             end) == ""
    end
  end

  describe "gimme_da_issue!/2 (Ruby: CLI::Issue#gimme_da_issue!)" do
    test "when already assigned to the caller, says so and doesn't reassign" do
      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" => %{
               "id" => "i1",
               "identifier" => "CRY-1",
               "title" => "Fix the thing",
               "branchName" => "cry-1-fix-the-thing",
               "description" => nil,
               "assignee" => %{
                 "id" => "u1",
                 "name" => "Ada",
                 "email" => "ada@x.com",
                 "teams" => %{"nodes" => []}
               },
               "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
               "comments" => %{"nodes" => []}
             }
           }
         }}
      ])

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      assert capture_io(fn ->
               assert {:ok, %Issue{identifier: "CRY-1"}} =
                        IssueHelpers.gimme_da_issue!("CRY-1", me: me)
             end) =~ "You are already assigned CRY-1"
    end

    test "when unassigned, self-assigns" do
      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" => %{
               "id" => "i1",
               "identifier" => "CRY-1",
               "title" => "Fix the thing",
               "branchName" => "cry-1-fix-the-thing",
               "description" => nil,
               "assignee" => nil,
               "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
               "comments" => %{"nodes" => []}
             }
           }
         }},
        {"issueUpdate",
         issue_updated(%{
           "assignee" => %{
             "id" => "u1",
             "name" => "Ada",
             "email" => "ada@x.com",
             "teams" => %{"nodes" => []}
           }
         })}
      ])

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      output =
        capture_io(fn ->
          assert {:ok, %Issue{assignee: %User{id: "u1"}}} =
                   IssueHelpers.gimme_da_issue!("CRY-1", me: me)
        end)

      assert output =~ "Assigning issue CRY-1 to ya"
    end

    test "when already assigned to someone else, self-assigns" do
      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" => %{
               "id" => "i1",
               "identifier" => "CRY-1",
               "title" => "Fix the thing",
               "branchName" => "cry-1-fix-the-thing",
               "description" => nil,
               "assignee" => %{
                 "id" => "u2",
                 "name" => "Bob",
                 "email" => "bob@x.com",
                 "teams" => %{"nodes" => []}
               },
               "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
               "comments" => %{"nodes" => []}
             }
           }
         }},
        {"issueUpdate",
         issue_updated(%{
           "assignee" => %{
             "id" => "u1",
             "name" => "Ada",
             "email" => "ada@x.com",
             "teams" => %{"nodes" => []}
           }
         })}
      ])

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      assert capture_io(fn ->
               assert {:ok, %Issue{assignee: %User{id: "u1"}}} =
                        IssueHelpers.gimme_da_issue!("CRY-1", me: me)
             end) =~ "Assigning issue CRY-1 to ya"
    end

    test "with status: opt, resolves state per team and sends stateId" do
      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" => %{
               "id" => "i1",
               "identifier" => "CRY-1",
               "title" => "Fix the thing",
               "branchName" => "cry-1-fix-the-thing",
               "description" => nil,
               "assignee" => nil,
               "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
               "comments" => %{"nodes" => []}
             }
           }
         }},
        {"states {",
         %{
           "data" => %{
             "team" => %{
               "states" => %{
                 "nodes" => [
                   %{
                     "id" => "s1",
                     "name" => "In Progress",
                     "position" => 1.0,
                     "type" => "started",
                     "description" => nil
                   }
                 ]
               }
             }
           }
         }},
        {"issueUpdate",
         issue_updated(%{
           "assignee" => %{
             "id" => "u1",
             "name" => "Ada",
             "email" => "ada@x.com",
             "teams" => %{"nodes" => []}
           }
         })}
      ])

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      capture_io(fn ->
        assert {:ok, %Issue{identifier: "CRY-1"}} =
                 IssueHelpers.gimme_da_issue!("CRY-1", me: me, status: "In Progress")
      end)
    end

    test "with status: opt, case-insensitive match sends correct stateId" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{
              "data" => %{
                "issue" => %{
                  "id" => "i1",
                  "identifier" => "CRY-1",
                  "title" => "Fix the thing",
                  "branchName" => "cry-1-fix-the-thing",
                  "description" => nil,
                  "assignee" => nil,
                  "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                  "comments" => %{"nodes" => []}
                }
              }
            })

          String.contains?(query, "states {") ->
            Req.Test.json(conn, %{
              "data" => %{
                "team" => %{
                  "states" => %{
                    "nodes" => [
                      %{
                        "id" => "s99",
                        "name" => "Todo",
                        "position" => 0.0,
                        "type" => "unstarted",
                        "description" => nil
                      }
                    ]
                  }
                }
              }
            })

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})

            Req.Test.json(
              conn,
              issue_updated(%{
                "assignee" => %{
                  "id" => "u1",
                  "name" => "Ada",
                  "email" => "ada@x.com",
                  "teams" => %{"nodes" => []}
                }
              })
            )

          true ->
            raise "no stub matched: #{query}"
        end
      end)

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      capture_io(fn ->
        assert {:ok, _} = IssueHelpers.gimme_da_issue!("CRY-1", me: me, status: "todo")
      end)

      assert_received {:input, input}
      assert input["stateId"] == "s99"
    end

    test "with status: opt, already-assigned still sends stateId mutation" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{
              "data" => %{
                "issue" => %{
                  "id" => "i1",
                  "identifier" => "CRY-1",
                  "title" => "Fix the thing",
                  "branchName" => "cry-1-fix-the-thing",
                  "description" => nil,
                  "assignee" => %{
                    "id" => "u1",
                    "name" => "Ada",
                    "email" => "ada@x.com",
                    "teams" => %{"nodes" => []}
                  },
                  "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                  "comments" => %{"nodes" => []}
                }
              }
            })

          String.contains?(query, "states {") ->
            Req.Test.json(conn, %{
              "data" => %{
                "team" => %{
                  "states" => %{
                    "nodes" => [
                      %{
                        "id" => "s2",
                        "name" => "In Progress",
                        "position" => 1.0,
                        "type" => "started",
                        "description" => nil
                      }
                    ]
                  }
                }
              }
            })

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})

            Req.Test.json(
              conn,
              issue_updated(%{
                "assignee" => %{
                  "id" => "u1",
                  "name" => "Ada",
                  "email" => "ada@x.com",
                  "teams" => %{"nodes" => []}
                }
              })
            )

          true ->
            raise "no stub matched: #{query}"
        end
      end)

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      capture_io(fn ->
        assert {:ok, _} = IssueHelpers.gimme_da_issue!("CRY-1", me: me, status: "In Progress")
      end)

      assert_received {:input, input}
      assert input["assigneeId"] == "u1"
      assert input["stateId"] == "s2"
    end

    test "with status: opt, unknown name returns smells_bad error" do
      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" => %{
               "id" => "i1",
               "identifier" => "CRY-1",
               "title" => "Fix the thing",
               "branchName" => "cry-1-fix-the-thing",
               "description" => nil,
               "assignee" => nil,
               "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
               "comments" => %{"nodes" => []}
             }
           }
         }},
        {"states {",
         %{
           "data" => %{
             "team" => %{
               "states" => %{
                 "nodes" => [
                   %{
                     "id" => "s1",
                     "name" => "Todo",
                     "position" => 0.0,
                     "type" => "unstarted",
                     "description" => nil
                   }
                 ]
               }
             }
           }
         }}
      ])

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      capture_io(fn ->
        assert {:error, {:smells_bad, msg}} =
                 IssueHelpers.gimme_da_issue!("CRY-1", me: me, status: "NoSuch")

        assert msg =~ "Unknown status"
      end)
    end
  end

  describe "create_pr!/3 and issue_pr/2" do
    test "create_pr!/3 forwards to the injectable runner" do
      runner = fn title, body -> "ran with #{title}/#{body}" end
      assert IssueHelpers.create_pr!("My title", "My body", runner) == "ran with My title/My body"
    end

    test "issue_pr/2 resolves title/description then prints the runner's output as a warning" do
      output =
        capture_io(fn ->
          assert :ok =
                   IssueHelpers.issue_pr(issue(),
                     title: "fix: CRY-1 - Fix the thing",
                     description: "body",
                     runner: fn title, body -> "gh said: #{title} (#{body})" end
                   )
        end)

      assert output =~ "gh said: fix: CRY-1 - Fix the thing (body)"
    end
  end
end
