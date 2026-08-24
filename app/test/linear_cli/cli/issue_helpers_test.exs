defmodule LinearCli.CLI.IssueHelpersTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.IssueHelpers
  alias LinearCli.Linear.{Comment, Issue, Project, Team, User, WorkflowState}

  # Every helper under test accepts an already-loaded resource struct (no
  # data-layer fetch happens inside these functions themselves, mirroring
  # `assign_issue/2`/`close_issue/2`/etc.'s own documented contract) - so
  # tests build issues/teams directly instead of stubbing a lookup for them.
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

  # Dispatches to one of `pairs` ({substring, response_map}) based on which
  # substring appears in the outgoing GraphQL document - every document in
  # this codebase has a distinguishing operation name/field
  # (`commentCreate`, `issueUpdate`, `states {`, `projects(first: 100`,
  # `issueCreate`, `viewer`, `issue(id: $id)`), so one stub per test can
  # drive an entire multi-call flow.
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

  defp comment_created(id \\ "c1") do
    %{"data" => %{"commentCreate" => %{"comment" => %{"id" => id, "body" => "x", "url" => "u"}}}}
  end

  defp issue_updated(overrides \\ %{}) do
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

  defp workflow_states(states) do
    %{"data" => %{"team" => %{"states" => %{"nodes" => states}}}}
  end

  defp team_projects(projects) do
    %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}
  end

  defp errors(message) do
    %{"errors" => [%{"message" => message}]}
  end

  describe "issue_comment/2 (Ruby: CLI::Issue#issue_comment)" do
    test "adds the comment and prints a confirmation" do
      stub_responses([{"commentCreate", comment_created()}])

      assert capture_io(fn ->
               assert {:ok, %Comment{id: "c1"}} = IssueHelpers.issue_comment(issue(), "lgtm")
             end) =~ "Comment added to CRY-1"
    end

    test "propagates the underlying error without printing anything" do
      stub_responses([{"commentCreate", errors("boom")}])

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Unknown{}} = IssueHelpers.issue_comment(issue(), "x")
             end) == ""
    end
  end

  describe "cancelled_state_for/1 and completed_state_for/1" do
    test "returns the sole matching state directly, no prompt" do
      stub_responses([
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"},
           %{"id" => "s2", "name" => "Done", "position" => 2.0, "type" => "completed"}
         ])}
      ])

      assert capture_io(fn ->
               assert {:ok, %WorkflowState{id: "s1"}} =
                        IssueHelpers.cancelled_state_for(issue())
             end) == ""
    end

    test "also matches the American 'canceled' spelling" do
      stub_responses([
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Canceled", "position" => 1.0, "type" => "canceled"}
         ])}
      ])

      assert {:ok, %WorkflowState{id: "s1"}} = IssueHelpers.cancelled_state_for(issue())
    end

    test "prompts to disambiguate when several states of the same type exist" do
      stub_responses([
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Done", "position" => 1.0, "type" => "completed"},
           %{"id" => "s2", "name" => "Shipped", "position" => 2.0, "type" => "completed"}
         ])}
      ])

      output =
        capture_io([input: "2\n"], fn ->
          assert {:ok, %WorkflowState{id: "s2"}} = IssueHelpers.completed_state_for(issue())
        end)

      assert output =~ "Choose a completed state"
    end

    test "returns a smells_bad error when the team has no state of that type" do
      stub_responses([
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Backlog", "position" => 1.0, "type" => "backlog"}
         ])}
      ])

      assert {:error, {:smells_bad, message}} = IssueHelpers.cancelled_state_for(issue())
      assert message =~ "No cancelled workflow states found for team ENG"
    end
  end

  describe "cancel_issue/2 (Ruby: CLI::Issue#cancel_issue)" do
    test "comments, resolves the cancelled state, and transitions the issue" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert {:ok, %Issue{identifier: "CRY-1"}} =
                   IssueHelpers.cancel_issue(issue(), reason: "no longer needed")
        end)

      assert output =~ "Comment added to CRY-1"
      assert output =~ "CRY-1 was cancelled"
    end

    test "surfaces the smells_bad error instead of attempting the transition" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {", workflow_states([])}
      ])

      assert capture_io(fn ->
               assert {:error, {:smells_bad, _message}} =
                        IssueHelpers.cancel_issue(issue(), reason: "no longer needed")
             end) =~ "Comment added to CRY-1"
    end

    test "is a no-op when the issue is already in a cancelled state" do
      already_cancelled =
        issue(%{state: %WorkflowState{id: "s1", name: "Cancelled", type: "cancelled"}})

      output =
        capture_io(fn ->
          assert {:ok, ^already_cancelled} =
                   IssueHelpers.cancel_issue(already_cancelled, reason: "no longer needed")
        end)

      assert output =~ "CRY-1 is already Cancelled"
      refute output =~ "Comment added"
    end
  end

  describe "close_issue/2 (Ruby: CLI::Issue#close_issue)" do
    test "closes (completed state) by default" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Done", "position" => 1.0, "type" => "completed"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert {:ok, %Issue{}} = IssueHelpers.close_issue(issue(), reason: "shipped")
        end)

      assert output =~ "CRY-1 was closed"
    end

    test "cancels (cancelled state) when opts[:cancel] is truthy" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert {:ok, %Issue{}} =
                   IssueHelpers.close_issue(issue(), cancel: true, reason: "nope")
        end)

      assert output =~ "CRY-1 was cancelled"
    end

    test "is a no-op when the issue is already in a completed state" do
      already_done = issue(%{state: %WorkflowState{id: "s1", name: "Done", type: "completed"}})

      output =
        capture_io(fn ->
          assert {:ok, ^already_done} = IssueHelpers.close_issue(already_done, reason: "shipped")
        end)

      assert output =~ "CRY-1 is already Done"
      refute output =~ "Comment added"
    end

    test "is a no-op when cancel: true and issue is already in a cancelled state" do
      already_cancelled =
        issue(%{state: %WorkflowState{id: "s1", name: "Cancelled", type: "cancelled"}})

      output =
        capture_io(fn ->
          assert {:ok, ^already_cancelled} =
                   IssueHelpers.close_issue(already_cancelled, cancel: true, reason: "nope")
        end)

      assert output =~ "CRY-1 is already Cancelled"
      refute output =~ "Comment added"
    end
  end

  describe "update_description/2" do
    test "resolves and sends the description, printing a confirmation" do
      stub_responses([{"issueUpdate", issue_updated(%{"description" => "New body"})}])

      assert capture_io(fn ->
               assert {:ok, %Issue{description: "New body"}} =
                        IssueHelpers.update_description(issue(), "New body")
             end) =~ "CRY-1 description updated"
    end

    test "propagates an API error without printing confirmation" do
      stub_responses([{"issueUpdate", %{"errors" => [%{"message" => "boom"}]}}])

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Invalid{}} =
                        IssueHelpers.update_description(issue(), "New body")
             end) == ""
    end
  end

  describe "move_issue/2" do
    test "moves the issue to the resolved project and prints a confirmation" do
      stub_responses([{"issueUpdate", issue_updated()}])

      project = %Project{id: "p1", name: "Manhattan Rollout"}

      assert capture_io(fn ->
               assert {:ok, %Issue{}} = IssueHelpers.move_issue(issue(), project)
             end) =~ "CRY-1 was moved to Manhattan Rollout"
    end

    test "propagates an API error without printing confirmation" do
      stub_responses([{"issueUpdate", %{"errors" => [%{"message" => "boom"}]}}])

      project = %Project{id: "p1", name: "Manhattan Rollout"}

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Invalid{}} = IssueHelpers.move_issue(issue(), project)
             end) == ""
    end
  end

  describe "attach_project/2 (Ruby: CLI::Issue#attach_project)" do
    test "resolves the project by name against the team's projects and attaches it" do
      stub_responses([
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
        {"issueUpdate", issue_updated()}
      ])

      assert capture_io(fn ->
               assert {:ok, %Issue{}} =
                        IssueHelpers.attach_project(issue(), "Manhattan Rollout")
             end) =~ "CRY-1 was moved to Manhattan Rollout"
    end
  end

  describe "update_issue/2 dispatch (Ruby: CLI::Issue#update_issue)" do
    test "with :close, comments then closes" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Done", "position" => 1.0, "type" => "completed"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert :ok = IssueHelpers.update_issue(issue(), close: true, reason: "done")
        end)

      assert output =~ "CRY-1 was closed"
    end

    test "with :cancel, comments then cancels" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert :ok = IssueHelpers.update_issue(issue(), cancel: true, reason: "nope")
        end)

      assert output =~ "CRY-1 was cancelled"
    end

    test "with :pr, opens a PR via the injectable runner and never calls the API" do
      output =
        capture_io(fn ->
          assert :ok =
                   IssueHelpers.update_issue(issue(),
                     pr: true,
                     title: "fix: CRY-1 - Fix the thing",
                     description: "body",
                     runner: fn _title, _body -> "https://github.com/x/y/pull/1" end
                   )
        end)

      assert output =~ "https://github.com/x/y/pull/1"
    end

    test "with :project, resolves and attaches" do
      stub_responses([
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
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert :ok = IssueHelpers.update_issue(issue(), project: "Manhattan Rollout")
        end)

      assert output =~ "CRY-1 was moved to Manhattan Rollout"
    end

    test "with :description, updates the issue description" do
      stub_responses([{"issueUpdate", issue_updated(%{"description" => "New body"})}])

      output =
        capture_io(fn ->
          assert :ok = IssueHelpers.update_issue(issue(), description: "New body")
        end)

      assert output =~ "CRY-1 description updated"
    end

    test "with only :comment, comments and stops without the 'no action taken' warning" do
      stub_responses([{"commentCreate", comment_created()}])

      output =
        capture_io(fn ->
          assert :ok = IssueHelpers.update_issue(issue(), comment: "fyi")
        end)

      assert output =~ "Comment added to CRY-1"
      refute output =~ "No action taken"
    end

    test "with no options at all, warns and reports no update, without calling the API" do
      output =
        capture_io(fn ->
          assert :ok = IssueHelpers.update_issue(issue())
        end)

      assert output =~ "No action taken, no options specified"
      assert output =~ "Issue was not updated"
    end

    test "an error from a dispatched action propagates as {:error, reason}" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {", errors("boom")}
      ])

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Unknown{}} =
                        IssueHelpers.update_issue(issue(), close: true, reason: "x")
             end) =~ "Comment added to CRY-1"
    end
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
