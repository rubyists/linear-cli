defmodule LinearCli.CLI.IssueCommandsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Commands
  alias LinearCli.Linear.User

  # Dispatches to one of `pairs` ({substring, response_map}) based on which
  # substring appears in the outgoing GraphQL document - see
  # `LinearCli.CLI.IssueHelpersTest`'s own `stub_responses/1` for why one
  # stub per test is enough to drive an entire multi-call flow.
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

  defp team_map, do: %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}

  defp me_map(overrides \\ %{}) do
    Map.merge(
      %{"id" => "u1", "name" => "Ada", "email" => "ada@x.com", "teams" => %{"nodes" => []}},
      overrides
    )
  end

  defp label_response(names) do
    %{
      "data" => %{
        "issueLabels" => %{
          "edges" =>
            Enum.map(names, fn name ->
              %{
                "node" => %{
                  "id" => "l-#{name}",
                  "name" => name,
                  "description" => nil,
                  "isGroup" => false
                }
              }
            end)
        }
      }
    }
  end

  defp project_map(id, name) do
    %{
      "id" => id,
      "name" => name,
      "content" => nil,
      "slugId" => "abc",
      "description" => nil,
      "url" => "https://linear.app/x/project/#{id}"
    }
  end

  defp team_projects(projects),
    do: %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}

  defp issue_map(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "i1",
        "identifier" => "CRY-1",
        "title" => "Fix the thing",
        "branchName" => "cry-1-fix-the-thing",
        "description" => "It is broken",
        "assignee" => nil,
        "state" => %{"id" => "s1", "name" => "In Progress", "type" => "started"},
        "team" => team_map(),
        "comments" => %{"nodes" => []}
      },
      overrides
    )
  end

  defp issue_updated(overrides \\ %{}) do
    %{"data" => %{"issueUpdate" => %{"issue" => issue_map(overrides)}}}
  end

  defp comment_created do
    %{
      "data" => %{"commentCreate" => %{"comment" => %{"id" => "c1", "body" => "x", "url" => "u"}}}
    }
  end

  defp workflow_states(states) do
    %{"data" => %{"team" => %{"states" => %{"nodes" => states}}}}
  end

  # Every git-touching test gets a fresh local repo (one commit on "main",
  # already pushed to/tracking a fresh bare "origin") under
  # `System.tmp_dir!()` - never the real project working directory. See house
  # rule 6 and `LinearCli.GitTest`'s own identical setup.
  defp git_repo! do
    origin_path = tmp_path("origin")
    File.mkdir_p!(origin_path)
    {_output, 0} = System.cmd("git", ["init", "--bare", "-q"], cd: origin_path)

    repo_path = tmp_path("repo")
    File.mkdir_p!(repo_path)
    {_output, 0} = System.cmd("git", ["init", "-q"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: repo_path)
    File.write!(Path.join(repo_path, "README.md"), "hello")
    {_output, 0} = System.cmd("git", ["add", "README.md"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["commit", "-q", "-m", "init"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["branch", "-M", "main"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["remote", "add", "origin", origin_path], cd: repo_path)
    {_output, 0} = System.cmd("git", ["push", "-q", "-u", "origin", "main"], cd: repo_path)

    on_exit(fn ->
      File.rm_rf!(origin_path)
      File.rm_rf!(repo_path)
    end)

    repo_path
  end

  defp tmp_path(prefix) do
    Path.join(
      System.tmp_dir!(),
      "linear_cli_issue_commands_test_#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
    )
  end

  # Workspace-wide (not team-scoped) projects query - the shape
  # `LinearCli.Linear.Project.Read.All`/`Linear.projects/0` actually use,
  # distinct from `team_projects/1`'s team-scoped `nodes` shape above.
  defp all_projects(projects) do
    %{
      "data" => %{
        "projects" => %{
          "edges" => Enum.map(projects, &%{"node" => &1, "cursor" => &1["id"]}),
          "pageInfo" => %{"hasNextPage" => false}
        }
      }
    }
  end

  defp issues_response(issues) do
    %{
      "data" => %{
        "issues" => %{
          "edges" => Enum.map(issues, &%{"node" => &1, "cursor" => &1["id"]}),
          "pageInfo" => %{"hasNextPage" => false}
        }
      }
    }
  end

  describe "issue list (Ruby: commands/issue/list.rb + operations/issue/list.rb)" do
    test "--project resolves against every workspace project and filters the issue query by it" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "projects(first: $first") ->
            Req.Test.json(conn, all_projects([project_map("p1", "Manhattan Rollout")]))

          String.contains?(query, "issues(filter") ->
            send(test_pid, {:filter, decoded["variables"]["filter"]})
            Req.Test.json(conn, issues_response([issue_map()]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--project", "Manhattan Rollout"])
        end)

      assert output =~ "CRY-1"
      assert_received {:filter, %{"project" => %{"id" => %{"eq" => "p1"}}}}
    end

    test "--project with --team resolves against team-scoped projects only" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "projects(first: $first") ->
            raise "--project with --team must not query all-workspace projects"

          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "projects(first: 100, filter: $filter)") ->
            filters = decoded["variables"]["filter"]["or"]

            assert %{"name" => %{"containsIgnoreCase" => "Wallet Service Extraction"}} in filters

            Req.Test.json(
              conn,
              team_projects([
                project_map("p2", "Wallet Service Extraction for Humans"),
                project_map("p1", "Wallet Service Extraction")
              ])
            )

          String.contains?(query, "issues(filter") ->
            send(test_pid, {:filter, decoded["variables"]["filter"]})
            Req.Test.json(conn, issues_response([issue_map()]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "list",
                     "--team",
                     "ENG",
                     "--project",
                     "Wallet Service Extraction"
                   ])
        end)

      assert output =~ "CRY-1"
      assert_received {:filter, %{"project" => %{"id" => %{"eq" => "p1"}}}}
    end

    test "bare issue list applies no project filter and never queries projects at all" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        if String.contains?(query, "projects(") do
          raise "issue list must not query projects when --project wasn't given"
        end

        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      output = capture_io(fn -> assert :ok = LinearCli.CLI.main(["issue", "list"]) end)
      assert output =~ "CRY-1"
    end

    test "-N aliases --no-mine" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "-N"])
      end)

      assert_received {:filter, filter}
      refute Map.has_key?(filter, "assignee")
    end

    test "--all removes completedAt and canceledAt null-check filters" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--all"])
      end)

      assert_received {:filter, filter}
      refute Map.has_key?(filter, "completedAt")
      refute Map.has_key?(filter, "canceledAt")
    end

    test "--state filters by workflow state type and removes corresponding date filters" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--state", "started"])
      end)

      assert_received {:filter, filter}
      assert filter["state"] == %{"type" => %{"in" => ["started"]}}
      # "started" is not completed/cancelled so both date filters remain
      assert Map.has_key?(filter, "completedAt")
      assert Map.has_key?(filter, "canceledAt")
    end

    test "--state completed removes completedAt filter but keeps canceledAt filter" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--state", "completed"])
      end)

      assert_received {:filter, filter}
      assert filter["state"] == %{"type" => %{"in" => ["completed"]}}
      refute Map.has_key?(filter, "completedAt")
      assert Map.has_key?(filter, "canceledAt")
    end

    test "--state accepts multiple comma-separated types" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--state", "started,completed"])
      end)

      assert_received {:filter, filter}
      assert filter["state"] == %{"type" => %{"in" => ["started", "completed"]}}
      refute Map.has_key?(filter, "completedAt")
      assert Map.has_key?(filter, "canceledAt")
    end

    test "--status filters by friendly workflow status name" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--status", "Human Review"])
      end)

      assert_received {:filter, filter}
      assert filter["state"] == %{"name" => %{"eqIgnoreCase" => "Human Review"}}
      refute Map.has_key?(filter, "completedAt")
      refute Map.has_key?(filter, "canceledAt")
    end

    test "--state and comma-separated --status values combine as type AND friendly name" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "list",
                   "--state",
                   "started",
                   "--status",
                   "Human Review, Gate Approved"
                 ])
      end)

      assert_received {:filter, filter}

      assert filter["state"] == %{
               "type" => %{"in" => ["started"]},
               "or" => [
                 %{"name" => %{"eqIgnoreCase" => "Human Review"}},
                 %{"name" => %{"eqIgnoreCase" => "Gate Approved"}}
               ]
             }

      assert Map.has_key?(filter, "completedAt")
      assert Map.has_key?(filter, "canceledAt")
    end

    test "--no-profile bypasses active profile defaults via the full CLI dispatch path" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "projects(") do
          raise "--no-profile must not query projects when --project wasn't given"
        end

        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--no-profile"])
        end)

      assert output =~ "CRY-1"
      assert_received {:filter, filter}
      refute Map.has_key?(filter, "team")
      refute Map.has_key?(filter, "project")
    end

    test "--state with an unknown type exits 1 (Optimus parse error)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      # Optimus catches the bad value and calls halt.(1); with a fake halt that
      # doesn't terminate the process, execution continues and eventually crashes
      # (same artifact as the --help test in cli_test.exs). Rescue it so the test
      # can still verify halt was called with the right code.
      try do
        LinearCli.CLI.main(["issue", "list", "--state", "badtype"], halt)
      rescue
        _ -> :ok
      end

      assert_received {:halted, 1}
    end

    test "compact listing includes workflow state name in brackets" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        if String.contains?(query, "projects(") do
          raise "issue list must not query projects when --project wasn't given"
        end

        Req.Test.json(
          conn,
          issues_response([
            issue_map(%{"state" => %{"id" => "s2", "name" => "In Review", "type" => "started"}})
          ])
        )
      end)

      output = capture_io(fn -> assert :ok = LinearCli.CLI.main(["issue", "list"]) end)
      assert output =~ "[In Review]"
      assert output =~ "Fix the thing"
    end

    test "compact listing omits state bracket when state is nil" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)
        Req.Test.json(conn, issues_response([issue_map(%{"state" => nil})]))
      end)

      output = capture_io(fn -> assert :ok = LinearCli.CLI.main(["issue", "list"]) end)
      assert output =~ "CRY-1"
      refute output =~ "["
    end

    test "--full listing includes workflow state name in header" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "issue" =>
              issue_map(%{"state" => %{"id" => "s3", "name" => "Done", "type" => "completed"}})
          }
        })
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--full", "CRY-1"])
        end)

      assert output =~ "[Done]"
      assert output =~ "Fix the thing"
    end
  end

  describe "issue create (Ruby: commands/issue/create.rb)" do
    test "resolves every field, declines to take it, and displays the created issue" do
      stub_responses([
        {"team(id: $id)", %{"data" => %{"team" => team_map()}}},
        {"issueLabels", label_response(["urgent"])},
        {"projects(first: 100", team_projects([project_map("p1", "Manhattan Rollout")])},
        {"issueCreate",
         %{
           "data" => %{
             "issueCreate" => %{
               "issue" =>
                 issue_map(%{
                   "id" => "i2",
                   "identifier" => "CRY-2",
                   "title" => "New thing",
                   "branchName" => "cry-2-new-thing",
                   "description" => "Some description"
                 })
             }
           }
         }}
      ])

      output =
        capture_io([input: "n\n"], fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "create",
                     "--title",
                     "New thing",
                     "--description",
                     "Some description",
                     "--team",
                     "ENG",
                     "-l",
                     "urgent",
                     "--project",
                     "Manhattan Rollout"
                   ])
        end)

      assert output =~ "Do you want to take this issue?"
      assert output =~ "CRY-2"
      assert output =~ "New thing"
    end

    test "--dev still checks out and pushes the new issue's branch after declining to take it" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      created_issue =
        issue_map(%{
          "id" => "i2",
          "identifier" => "CRY-2",
          "title" => "New thing",
          "branchName" => "cry-2-new-thing",
          "description" => "Some description",
          "assignee" => me_map()
        })

      stub_responses([
        {"team(id: $id)", %{"data" => %{"team" => team_map()}}},
        {"issueLabels", label_response(["urgent"])},
        {"projects(first: 100", team_projects([project_map("p1", "Manhattan Rollout")])},
        {"issueCreate", %{"data" => %{"issueCreate" => %{"issue" => created_issue}}}},
        {"issue(id: $id)", %{"data" => %{"issue" => created_issue}}}
      ])

      result = %{
        options: %{
          title: "New thing",
          description: "Some description",
          team: "ENG",
          labels: ["urgent"],
          project: "Manhattan Rollout",
          output: "text"
        },
        flags: %{develop: true}
      }

      output =
        capture_io([input: "n\n"], fn ->
          assert :ok = Commands.issue_create(result, cwd: repo, me: me)
        end)

      assert output =~ "Checked out branch cry-2-new-thing"
      assert output =~ "Upstream branch not found, pushing local cry-2-new-thing to origin"
      assert output =~ "Set upstream to origin/cry-2-new-thing"
      assert output =~ "Ready to develop!"
    end
  end

  describe "issue develop (Ruby: commands/issue/develop.rb)" do
    test "resolves/self-assigns the issue, checks out its branch, and pulls" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      stub_responses([
        {"issue(id: $id)",
         %{"data" => %{"issue" => issue_map(%{"branchName" => "main", "assignee" => me_map()})}}}
      ])

      result = %{args: %{issue_id: "CRY-1"}}

      output =
        capture_io(fn ->
          assert :ok = Commands.issue_develop(result, cwd: repo, me: me)
        end)

      assert output =~ "You are already assigned CRY-1"
      assert output =~ "Checked out branch main"
      assert output =~ "Ready to develop!"
      refute output =~ "Upstream branch not found"
    end

    test "pushes a new branch and sets its upstream when the branch has no tracking branch yet" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" =>
               issue_map(%{"branchName" => "cry-1-fix-the-thing", "assignee" => me_map()})
           }
         }}
      ])

      result = %{args: %{issue_id: "CRY-1"}}

      output =
        capture_io(fn ->
          assert :ok = Commands.issue_develop(result, cwd: repo, me: me)
        end)

      assert output =~ "Checked out branch cry-1-fix-the-thing"
      assert output =~ "Upstream branch not found, pushing local cry-1-fix-the-thing to origin"
      assert output =~ "Set upstream to origin/cry-1-fix-the-thing"
      assert output =~ "Ready to develop!"
    end
  end

  describe "issue pr (Ruby: commands/issue/pr.rb)" do
    test "checks out the issue's branch (no pull/push) and opens a PR via the injectable runner" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      stub_responses([
        {"issue(id: $id)",
         %{"data" => %{"issue" => issue_map(%{"branchName" => "main", "assignee" => me_map()})}}}
      ])

      result = %{
        args: %{issue_id: "CRY-1"},
        options: %{title: "fix: CRY-1 - Fix the thing", description: "body"}
      }

      output =
        capture_io(fn ->
          assert :ok =
                   Commands.issue_pr(result,
                     cwd: repo,
                     me: me,
                     runner: fn title, body -> "gh said: #{title} (#{body})" end
                   )
        end)

      assert output =~ "Checked out branch main"
      assert output =~ "gh said: fix: CRY-1 - Fix the thing (body)"
      refute output =~ "Ready to develop!"
    end
  end

  describe "issue take (Ruby: commands/issue/take.rb)" do
    test "self-assigns unassigned issues and warns, but doesn't abort, on an unknown id" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]
        variables = decoded["variables"] || %{}

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => me_map()}})

          query =~ "issue(id: $id)" and variables["id"] == "CRY-1" ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map(%{"assignee" => nil})}})

          query =~ "issue(id: $id)" and variables["id"] == "NOPE" ->
            Req.Test.json(conn, %{"data" => %{"issue" => nil}})

          query =~ "issueUpdate" ->
            Req.Test.json(conn, issue_updated(%{"assignee" => me_map()}))
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "take", "CRY-1", "nope"])
        end)

      assert output =~ "Assigning issue CRY-1 to ya"
      assert output =~ "No issue found with id nope"
      assert output =~ "CRY-1"
    end
  end

  describe "issue status" do
    defp state_map(id, name, position, type) do
      %{"id" => id, "name" => name, "position" => position, "type" => type, "description" => nil}
    end

    defp issue_with_state(state_id, state_name) do
      issue_map(%{"state" => %{"id" => state_id, "name" => state_name, "type" => "started"}})
    end

    defp states_response do
      workflow_states([
        state_map("s1", "Triage", 0.0, "triage"),
        state_map("s2", "In Progress", 1.0, "started"),
        state_map("s3", "Done", 2.0, "completed")
      ])
    end

    test "--status sets the workflow state by exact name (case-insensitive)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            body_decoded = Jason.decode!(body)
            send(test_pid, {:state_id, body_decoded["variables"]["input"]["stateId"]})

            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "status", "--status", "done", "CRY-1"])
        end)

      assert_received {:state_id, "s3"}
      assert output =~ "CRY-1"
      assert output =~ "status set to Done"
    end

    test "--status updates multiple issue IDs concurrently and emits a JSON array" do
      test_pid = self()

      issue_details = fn
        "CRY-1" -> {"i1", "t1", "ENG", "Engineering", "s-eng-done"}
        "CRY-2" -> {"i2", "t2", "OPS", "Operations", "s-ops-done"}
      end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded
        variables = decoded["variables"] || %{}

        cond do
          String.contains?(query, "issue(id: $id)") ->
            identifier = variables["id"]
            {id, team_id, team_key, team_name, _state_id} = issue_details.(identifier)

            Req.Test.json(conn, %{
              "data" => %{
                "issue" =>
                  issue_map(%{
                    "id" => id,
                    "identifier" => identifier,
                    "team" => %{"id" => team_id, "key" => team_key, "name" => team_name}
                  })
              }
            })

          String.contains?(query, "states {") ->
            team_id = variables["teamId"]
            state_id = if team_id == "t1", do: "s-eng-done", else: "s-ops-done"
            send(test_pid, {:states_queried, team_id})
            Req.Test.json(conn, workflow_states([state_map(state_id, "Done", 1.0, "completed")]))

          String.contains?(query, "issueUpdate") ->
            identifier = variables["id"]
            state_id = variables["input"]["stateId"]
            {id, team_id, team_key, team_name, ^state_id} = issue_details.(identifier)
            update_pid = self()
            send(test_pid, {:status_update_started, identifier, state_id, update_pid})

            receive do
              :finish_status_update -> :ok
            after
              2_000 -> raise "status update was not released by the concurrency assertion"
            end

            Req.Test.json(conn, %{
              "data" => %{
                "issueUpdate" => %{
                  "issue" =>
                    issue_map(%{
                      "id" => id,
                      "identifier" => identifier,
                      "team" => %{"id" => team_id, "key" => team_key, "name" => team_name},
                      "state" => %{"id" => state_id, "name" => "Done", "type" => "completed"}
                    })
                }
              }
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      command =
        Task.async(fn ->
          capture_io(fn ->
            assert :ok =
                     LinearCli.CLI.main([
                       "issue",
                       "status",
                       "--status",
                       "Done",
                       "--output",
                       "json",
                       "CRY-1",
                       "CRY-2"
                     ])
          end)
        end)

      assert_receive {:status_update_started, "CRY-1", "s-eng-done", first_update}, 1_000
      assert_receive {:status_update_started, "CRY-2", "s-ops-done", second_update}, 1_000
      send(first_update, :finish_status_update)
      send(second_update, :finish_status_update)

      output = Task.await(command)

      assert_received {:states_queried, "t1"}
      assert_received {:states_queried, "t2"}

      assert {:ok, decoded} = Jason.decode(output)
      assert Enum.map(decoded, & &1["identifier"]) == ["CRY-1", "CRY-2"]
    end

    test "variadic issue IDs do not swallow unrecognized options" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            ["issue", "status", "--statuz", "Done", "CRY-1", "CRY-2"],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert stderr =~ "unrecognized option(s): --statuz"
    end

    test "-s short flag also sets the workflow state" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            body_decoded = Jason.decode!(body)
            send(test_pid, {:state_id, body_decoded["variables"]["input"]["stateId"]})

            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "status", "-s", "Done", "CRY-1"])
        end)

      assert_received {:state_id, "s3"}
      assert output =~ "status set to Done"
    end

    test "--status with prefix match selects unique match" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            body_decoded = Jason.decode!(body)
            send(test_pid, {:state_id, body_decoded["variables"]["input"]["stateId"]})

            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s2", "In Progress")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "status", "--status", "in", "CRY-1"])
        end)

      assert_received {:state_id, "s2"}
      assert output =~ "status set to In Progress"
    end

    test "--status with unknown name exits 22 (smells bad)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "status", "--status", "Nonexistent", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      assert stderr =~ "Unknown status"
      assert stderr =~ "This smells bad! Bailing."
    end

    test "--status with ambiguous prefix exits 22 (smells bad)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            # Two states starting with "D" to trigger ambiguity
            Req.Test.json(
              conn,
              workflow_states([
                state_map("s1", "Done", 1.0, "completed"),
                state_map("s2", "Doing", 2.0, "started")
              ])
            )

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "status", "--status", "Do", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      assert stderr =~ "Ambiguous status"
      assert stderr =~ "This smells bad! Bailing."
    end

    test "--comment adds a comment before changing the status" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "commentCreate") ->
            send(test_pid, :comment_created)
            Req.Test.json(conn, comment_created())

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "status",
                     "--status",
                     "Done",
                     "--comment",
                     "Wrapping up",
                     "CRY-1"
                   ])
        end)

      assert_received :comment_created
      assert output =~ "Comment added to CRY-1"
      assert output =~ "status set to Done"
    end

    test "interactive selection (no --status) prompts from sorted states" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      # Select the third option ("Done") interactively via stdin
      output =
        capture_io([input: "3\n"], fn ->
          assert :ok = LinearCli.CLI.main(["issue", "status", "CRY-1"])
        end)

      assert output =~ "Choose a status"
      assert output =~ "status set to Done"
    end

    test "--output json emits structured output" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "status",
                     "--status",
                     "Done",
                     "--output",
                     "json",
                     "CRY-1"
                   ])
        end)

      assert {:ok, decoded} = Jason.decode(output)
      assert decoded["identifier"] == "CRY-1"
    end

    test "alias 's' routes to issue status" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :updated)

            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "s", "--status", "Done", "CRY-1"])
      end)

      assert_received :updated
    end

    test "alias 'st' routes to issue status" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :updated)

            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "st", "--status", "Done", "CRY-1"])
      end)

      assert_received :updated
    end

    test "alias 'stat' routes to issue status" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "states {") ->
            Req.Test.json(conn, states_response())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :updated)

            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_with_state("s3", "Done")}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "stat", "--status", "Done", "CRY-1"])
      end)

      assert_received :updated
    end
  end

  describe "issue update (Ruby: commands/issue/update.rb)" do
    test "--close --status selects a completed state without prompting" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "commentCreate") ->
            Req.Test.json(conn, comment_created())

          String.contains?(query, "states {") ->
            Req.Test.json(
              conn,
              workflow_states([
                %{"id" => "s1", "name" => "Done", "position" => 1.0, "type" => "completed"},
                %{
                  "id" => "s2",
                  "name" => "Shipped",
                  "position" => 2.0,
                  "type" => "completed"
                }
              ])
            )

          String.contains?(query, "issueUpdate") ->
            assert decoded["variables"]["input"] == %{"stateId" => "s2"}
            send(test_pid, :closed_as_shipped)
            Req.Test.json(conn, issue_updated())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "update",
                     "--close",
                     "--status",
                     "ship",
                     "--reason",
                     "Done",
                     "CRY-1"
                   ])
        end)

      assert output =~ "Comment added to CRY-1"
      assert output =~ "CRY-1 was closed"
      refute output =~ "Choose a completed state"
      assert_received :closed_as_shipped
    end

    test "--description updates the issue description via the issueUpdate mutation" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:description, decoded["variables"]["input"]["description"]})
            Req.Test.json(conn, issue_updated(%{"description" => "Updated body"}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "update",
                     "--description",
                     "Updated body",
                     "CRY-1"
                   ])
        end)

      assert_received {:description, "Updated body"}
      assert output =~ "CRY-1 description updated"
    end

    test "-d short flag also updates the issue description" do
      stub_responses([
        {"issue(id: $id)", %{"data" => %{"issue" => issue_map()}}},
        {"issueUpdate", issue_updated(%{"description" => "Short flag body"})}
      ])

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "update",
                     "-d",
                     "Short flag body",
                     "CRY-1"
                   ])
        end)

      assert output =~ "CRY-1 description updated"
    end

    test "with no issue ids, exits 22 (Ruby: raise SmellsBad -> exit 22)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "update"], halt)
        end)

      assert_received {:halted, 22}
      assert output =~ "No issue IDs provided!"
      assert output =~ "This smells bad! Bailing."
    end
  end

  describe "issue assign" do
    defp member_map(id, name, email \\ nil) do
      %{"id" => id, "name" => name, "email" => email || "#{id}@example.com"}
    end

    defp members_response(members) do
      %{"data" => %{"team" => %{"members" => %{"nodes" => members}}}}
    end

    defp issue_assigned(assignee_map) do
      %{"data" => %{"issueUpdate" => %{"issue" => issue_map(%{"assignee" => assignee_map})}}}
    end

    test "--assignee sets the assignee by exact name (case-insensitive)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        decoded = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              members_response([member_map("u2", "Bob"), member_map("u3", "Alice")])
            )

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:assignee_id, decoded["variables"]["input"]["assigneeId"]})
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "assign", "--assignee", "bob", "CRY-1"])
        end)

      assert_received {:assignee_id, "u2"}
      assert output =~ "assigned to Bob"
    end

    test "--assignee prefix match selects unique match" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        decoded = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              members_response([member_map("u2", "Bob"), member_map("u3", "Alice")])
            )

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:assignee_id, decoded["variables"]["input"]["assigneeId"]})
            Req.Test.json(conn, issue_assigned(member_map("u3", "Alice")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "assign", "--assignee", "Ali", "CRY-1"])
        end)

      assert_received {:assignee_id, "u3"}
      assert output =~ "assigned to Alice"
    end

    test "--assignee with unknown name exits 22 (smells bad)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              members_response([member_map("u2", "Bob"), member_map("u3", "Alice")])
            )

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "assign", "--assignee", "Nobody", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      assert stderr =~ "Unknown assignee"
      assert stderr =~ "This smells bad! Bailing."
    end

    test "--assignee with ambiguous prefix exits 22 (smells bad)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              members_response([member_map("u2", "Bob"), member_map("u3", "Bobby")])
            )

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "assign", "--assignee", "Bo", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      assert stderr =~ "Ambiguous assignee"
      assert stderr =~ "This smells bad! Bailing."
    end

    test "interactive selection (no --assignee) prompts from sorted members" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              members_response([member_map("u2", "Bob"), member_map("u3", "Alice")])
            )

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, issue_assigned(member_map("u3", "Alice")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      # Members are sorted by name: Alice (1), Bob (2) — select "1\n" for Alice
      output =
        capture_io([input: "1\n"], fn ->
          assert :ok = LinearCli.CLI.main(["issue", "assign", "CRY-1"])
        end)

      assert output =~ "Choose an assignee"
      assert output =~ "assigned to Alice"
    end

    test "--output json emits structured output" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "assign",
                     "--assignee",
                     "Bob",
                     "--output",
                     "json",
                     "CRY-1"
                   ])
        end)

      assert {:ok, decoded} = Jason.decode(output)
      assert decoded["identifier"] == "CRY-1"
    end

    test "alias 'a' routes to issue assign" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :assigned)
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "a", "--assignee", "Bob", "CRY-1"])
      end)

      assert_received :assigned
    end

    test "no assignable members exits 22 (smells bad)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "assign", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      assert stderr =~ "No assignable members"
      assert stderr =~ "This smells bad! Bailing."
    end

    test "--status sends assigneeId and stateId in one issueUpdate" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "states {") ->
            Req.Test.json(
              conn,
              workflow_states([
                state_map("s2", "In Progress", 1.0, "started")
              ])
            )

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})

            Req.Test.json(
              conn,
              issue_assigned(member_map("u2", "Bob"))
              |> put_in(
                ["data", "issueUpdate", "issue", "state"],
                %{"id" => "s2", "name" => "In Progress", "type" => "started"}
              )
            )

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "assign",
                     "--assignee",
                     "Bob",
                     "--status",
                     "In Progress",
                     "CRY-1"
                   ])
        end)

      assert_received {:input, input}
      assert input["assigneeId"] == "u2"
      assert input["stateId"] == "s2"
      assert output =~ "assigned to Bob"
      assert output =~ "In Progress"
    end

    test "--status short form -s also works on assign" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "states {") ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main(["issue", "assign", "-a", "Bob", "-s", "Todo", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input["stateId"] == "s1"
    end

    test "--status with case-insensitive name match on assign" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "states {") ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main(["issue", "assign", "-a", "Bob", "--status", "todo", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input["stateId"] == "s1"
    end

    test "--status unknown name exits 22 before sending any mutation on assign" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "states {") ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutated)
            raise "issueUpdate should not be called when status is invalid"

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            ["issue", "assign", "-a", "Bob", "--status", "NoSuchState", "CRY-1"],
            halt
          )
        end)

      assert_received {:halted, 22}
      refute_received :mutated
      assert stderr =~ "Unknown status"
    end

    test "omitting --status sends only assigneeId (backward compat) on assign" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "assign", "-a", "Bob", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input == %{"assigneeId" => "u2"}
      refute Map.has_key?(input, "stateId")
    end

    test "--output json with --status returns structured output on assign" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "states {") ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(
              conn,
              issue_assigned(member_map("u2", "Bob"))
              |> put_in(
                ["data", "issueUpdate", "issue", "state"],
                %{"id" => "s1", "name" => "Todo", "type" => "unstarted"}
              )
            )

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "assign",
                     "-a",
                     "Bob",
                     "--status",
                     "Todo",
                     "--output",
                     "json",
                     "CRY-1"
                   ])
        end)

      assert {:ok, decoded} = Jason.decode(output)
      assert decoded["identifier"] == "CRY-1"
      assert decoded["state"]["name"] == "Todo"
    end

    test "--status with space in name works on assign" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(conn, members_response([member_map("u2", "Bob")]))

          String.contains?(query, "states {") ->
            Req.Test.json(
              conn,
              workflow_states([state_map("s-ip", "In Progress", 1.0, "started")])
            )

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_assigned(member_map("u2", "Bob")))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "assign",
                   "-a",
                   "Bob",
                   "--status",
                   "In Progress",
                   "CRY-53"
                 ])
      end)

      assert_received {:input, input}
      assert input["stateId"] == "s-ip"
    end
  end

  describe "issue take with --status" do
    defp take_member_map, do: %{"id" => "u1", "name" => "Ada", "email" => "ada@x.com"}

    defp take_issue_map(overrides \\ %{}) do
      Map.merge(
        %{
          "id" => "i1",
          "identifier" => "CRY-1",
          "title" => "Fix the thing",
          "branchName" => "cry-1-fix-the-thing",
          "description" => nil,
          "assignee" => nil,
          "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
          "comments" => %{"nodes" => []}
        },
        overrides
      )
    end

    test "--status sends both assigneeId and stateId in one issueUpdate" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" ->
            Req.Test.json(conn, %{"data" => %{"issue" => take_issue_map()}})

          query =~ "states {" ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          query =~ "issueUpdate" ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => take_member_map()}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "take", "--status", "Todo", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input["assigneeId"] == "u1"
      assert input["stateId"] == "s1"
    end

    test "-s short form works on take" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" ->
            Req.Test.json(conn, %{"data" => %{"issue" => take_issue_map()}})

          query =~ "states {" ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          query =~ "issueUpdate" ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => take_member_map()}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "take", "-s", "Todo", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input["stateId"] == "s1"
    end

    test "already-self-assigned issue still updates status when --status given" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" ->
            Req.Test.json(
              conn,
              %{
                "data" => %{
                  "issue" => take_issue_map(%{"assignee" => take_member_map()})
                }
              }
            )

          query =~ "states {" ->
            Req.Test.json(conn, workflow_states([state_map("s2", "In Progress", 1.0, "started")]))

          query =~ "issueUpdate" ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => take_member_map()}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main(["issue", "take", "--status", "In Progress", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input["assigneeId"] == "u1"
      assert input["stateId"] == "s2"
    end

    test "--status unknown name exits 22 before any mutation on take" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" ->
            Req.Test.json(conn, %{"data" => %{"issue" => take_issue_map()}})

          query =~ "states {" ->
            Req.Test.json(conn, workflow_states([state_map("s1", "Todo", 0.0, "unstarted")]))

          query =~ "issueUpdate" ->
            send(test_pid, :mutated)
            raise "issueUpdate should not be called"

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "take", "--status", "Bogus", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      refute_received :mutated
      assert stderr =~ "Unknown status"
    end

    test "omitting --status sends only assigneeId on take (backward compat)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" ->
            Req.Test.json(conn, %{"data" => %{"issue" => take_issue_map()}})

          query =~ "issueUpdate" ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => take_member_map()}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "take", "CRY-1"])
      end)

      assert_received {:input, input}
      assert input == %{"assigneeId" => "u1"}
      refute Map.has_key?(input, "stateId")
    end

    test "multiple issues from different teams resolve status independently" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded
        variables = decoded["variables"] || %{}

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" and variables["id"] == "CRY-1" ->
            Req.Test.json(
              conn,
              %{
                "data" => %{
                  "issue" =>
                    take_issue_map(%{
                      "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
                    })
                }
              }
            )

          query =~ "issue(id: $id)" and variables["id"] == "CRY-2" ->
            Req.Test.json(
              conn,
              %{
                "data" => %{
                  "issue" =>
                    take_issue_map(%{
                      "id" => "i2",
                      "identifier" => "CRY-2",
                      "team" => %{"id" => "t2", "key" => "OPS", "name" => "Operations"}
                    })
                }
              }
            )

          query =~ "states {" and variables["teamId"] == "t1" ->
            Req.Test.json(
              conn,
              workflow_states([state_map("s-eng-todo", "Todo", 0.0, "unstarted")])
            )

          query =~ "states {" and variables["teamId"] == "t2" ->
            Req.Test.json(
              conn,
              workflow_states([state_map("s-ops-todo", "Todo", 0.0, "unstarted")])
            )

          query =~ "issueUpdate" ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => take_member_map()}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "take", "--status", "Todo", "CRY-1", "CRY-2"])
      end)

      assert_received {:input, input1}
      assert_received {:input, input2}

      state_ids = MapSet.new([input1["stateId"], input2["stateId"]])
      assert MapSet.member?(state_ids, "s-eng-todo")
      assert MapSet.member?(state_ids, "s-ops-todo")
    end

    test "--status with space in name works on take" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => take_member_map()}})

          query =~ "issue(id: $id)" ->
            Req.Test.json(conn, %{"data" => %{"issue" => take_issue_map()}})

          query =~ "states {" ->
            Req.Test.json(
              conn,
              workflow_states([state_map("s-ip", "In Progress", 1.0, "started")])
            )

          query =~ "issueUpdate" ->
            send(test_pid, {:input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => take_member_map()}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "take", "--status", "In Progress", "CRY-53"])
      end)

      assert_received {:input, input}
      assert input["stateId"] == "s-ip"
    end
  end

  describe "issue move" do
    defp move_project_map(id \\ "p1", name \\ "Manhattan") do
      %{
        "id" => id,
        "name" => name,
        "content" => nil,
        "slugId" => "abc",
        "description" => nil,
        "url" => "https://linear.app/x/project/#{id}"
      }
    end

    defp move_team_projects(projects \\ nil) do
      nodes = projects || [move_project_map()]
      %{"data" => %{"team" => %{"projects" => %{"nodes" => nodes}}}}
    end

    defp issue_moved(project_map \\ nil) do
      project = project_map || move_project_map()
      %{"data" => %{"issueUpdate" => %{"issue" => issue_map(%{"project" => project})}}}
    end

    test "--project moves a single issue with --yes (no prompt)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:project_id, decoded["variables"]["input"]["projectId"]})
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--project",
                     "Manhattan",
                     "--yes",
                     "CRY-1"
                   ])
        end)

      assert_received {:project_id, "p1"}
      assert output =~ "CRY-1 -> Manhattan"
      assert output =~ "CRY-1 moved to Manhattan"
    end

    test "--dry-run prints the plan but does not call issueUpdate" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutation_called)
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--project",
                     "Manhattan",
                     "--dry-run",
                     "CRY-1"
                   ])
        end)

      refute_received :mutation_called
      assert output =~ "CRY-1 -> Manhattan"
      refute output =~ "moved to"
    end

    test "user declines confirmation, no mutation called" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutation_called)
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io([input: "n\n"], fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--project",
                     "Manhattan",
                     "CRY-1"
                   ])
        end)

      refute_received :mutation_called
      assert output =~ "CRY-1 -> Manhattan"
      assert output =~ "Move cancelled"
    end

    test "user confirms, mutation is called" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutation_called)
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io([input: "y\n"], fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "move",
                   "--project",
                   "Manhattan",
                   "CRY-1"
                 ])
      end)

      assert_received :mutation_called
    end

    test "moves multiple issues concurrently with --yes" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            identifier = decoded["variables"]["id"]

            issue =
              issue_map(%{
                "identifier" => identifier,
                "id" => "i-#{identifier}"
              })

            Req.Test.json(conn, %{"data" => %{"issue" => issue}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            identifier = decoded["variables"]["id"]
            send(test_pid, {:moved, identifier})
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--project",
                     "Manhattan",
                     "--yes",
                     "CRY-1",
                     "CRY-2"
                   ])
        end)

      assert_received {:moved, "CRY-1"}
      assert_received {:moved, "CRY-2"}
      assert output =~ "CRY-1 -> Manhattan"
      assert output =~ "CRY-2 -> Manhattan"
    end

    test "--output json emits issue JSON without confirmation messages" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--project",
                     "Manhattan",
                     "--yes",
                     "--output",
                     "json",
                     "CRY-1"
                   ])
        end)

      assert {:ok, decoded} = Jason.decode(String.trim(output))
      assert decoded["identifier"] == "CRY-1"
      refute output =~ "moved to"
      refute output =~ "->"
    end

    test "with no issue ids, exits 22 (smells bad)" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "move", "--project", "Manhattan"], halt)
        end)

      assert_received {:halted, 22}
      assert output =~ "No issue IDs provided!"
    end

    test "alias 'm' routes to issue move" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :moved)
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main(["issue", "m", "--project", "Manhattan", "--yes", "CRY-1"])
      end)

      assert_received :moved
    end

    test "alias 'mv' routes to issue move" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :moved)
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main(["issue", "mv", "--project", "Manhattan", "--yes", "CRY-1"])
      end)

      assert_received :moved
    end

    test "--team scopes project search to the given team" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          # Team.Read.Find uses "query($id: String!) { team(id: $id) { ... projects ... } }"
          String.contains?(query, "team(id: $id)") && String.contains?(query, "projects") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "projects(first: 100") ->
            send(test_pid, {:team_id, decoded["variables"]["teamId"]})
            Req.Test.json(conn, move_team_projects())

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, issue_moved())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "move",
                   "--project",
                   "Manhattan",
                   "--team",
                   "ENG",
                   "--yes",
                   "CRY-1"
                 ])
      end)

      assert_received {:team_id, "t1"}
    end

    # ── Bulk project-to-project mode (--from / --to) ──────────────────────

    defp bulk_issues do
      [
        issue_map(%{"id" => "i1", "identifier" => "CRY-1"}),
        issue_map(%{"id" => "i2", "identifier" => "CRY-2"}),
        issue_map(%{"id" => "i3", "identifier" => "CRY-3"})
      ]
    end

    defp bulk_stub_pairs do
      [
        {"$teamId",
         team_projects([
           project_map("p-src", "Source Project"),
           project_map("p-tgt", "Target Project")
         ])},
        {"team(id: $id)", %{"data" => %{"team" => team_map()}}},
        {"issues(filter:", issues_response(bulk_issues())},
        {"issueUpdate", issue_updated()}
      ]
    end

    test "--from/--to moves all open issues from source to target (happy path)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        if String.contains?(query, "issueUpdate") do
          send(test_pid, {:update, decoded["variables"]})
        end

        case Enum.find(bulk_stub_pairs(), fn {match, _} -> String.contains?(query, match) end) do
          {_match, response} -> Req.Test.json(conn, response)
          nil -> raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--from",
                     "Source Project",
                     "--to",
                     "Target Project",
                     "--team",
                     "ENG",
                     "--yes"
                   ])
        end)

      assert output =~ "Target Project"

      assert_received {:update, vars1}
      assert vars1["input"]["projectId"] == "p-tgt"
      assert_received {:update, vars2}
      assert vars2["input"]["projectId"] == "p-tgt"
      assert_received {:update, vars3}
      assert vars3["input"]["projectId"] == "p-tgt"
    end

    test "--from/--to --all sends list query without completedAt/canceledAt guards" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        %{"query" => query} = decoded

        if String.contains?(query, "issues(filter:") do
          filter = decoded["variables"]["filter"]
          send(test_pid, {:filter, filter})
        end

        case Enum.find(bulk_stub_pairs(), fn {match, _} -> String.contains?(query, match) end) do
          {_match, response} -> Req.Test.json(conn, response)
          nil -> raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "move",
                   "--from",
                   "Source Project",
                   "--to",
                   "Target Project",
                   "--team",
                   "ENG",
                   "--yes",
                   "--all"
                 ])
      end)

      assert_received {:filter, filter}
      refute Map.has_key?(filter, "completedAt")
      refute Map.has_key?(filter, "canceledAt")
    end

    test "--from/--to --dry-run resolves issues but sends no issueUpdate" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        if String.contains?(query, "issueUpdate") do
          raise "--dry-run must not send any issueUpdate"
        end

        case Enum.find(bulk_stub_pairs(), fn {match, _} -> String.contains?(query, match) end) do
          {_match, response} -> Req.Test.json(conn, response)
          nil -> raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--from",
                     "Source Project",
                     "--to",
                     "Target Project",
                     "--team",
                     "ENG",
                     "--dry-run"
                   ])
        end)

      assert output =~ "Would move"
    end

    test "--from/--to error mid-batch halts with non-zero exit" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end
      call_count = :counters.new(1, [])

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "$teamId") ->
            Req.Test.json(
              conn,
              team_projects([
                project_map("p-src", "Source Project"),
                project_map("p-tgt", "Target Project")
              ])
            )

          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "issues(filter:") ->
            Req.Test.json(conn, issues_response(bulk_issues()))

          String.contains?(query, "issueUpdate") ->
            :counters.add(call_count, 1, 1)
            n = :counters.get(call_count, 1)

            if n >= 2 do
              Req.Test.json(conn, %{"errors" => [%{"message" => "update failed"}]})
            else
              Req.Test.json(conn, issue_updated())
            end

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(:stderr, fn ->
        LinearCli.CLI.main(
          [
            "issue",
            "move",
            "--from",
            "Source Project",
            "--to",
            "Target Project",
            "--team",
            "ENG",
            "--yes"
          ],
          halt
        )
      end)

      assert_received {:halted, _code}
    end

    test "--from/--to --output json emits JSON array of moved issues" do
      stub_responses(bulk_stub_pairs())

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--from",
                     "Source Project",
                     "--to",
                     "Target Project",
                     "--team",
                     "ENG",
                     "--yes",
                     "--output",
                     "json"
                   ])
        end)

      assert {:ok, decoded} = Jason.decode(output)
      assert is_list(decoded)
      assert length(decoded) == 3
    end

    test "--from/--to UUID skips project-search queries" do
      src_uuid = "00000000-0000-1000-8000-000000000001"
      tgt_uuid = "00000000-0000-1000-8000-000000000002"

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        if String.contains?(query, "$teamId") do
          raise "UUID --from/--to must not send any project-search query"
        end

        cond do
          String.contains?(query, "issues(filter:") ->
            Req.Test.json(conn, issues_response(bulk_issues()))

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, issue_updated())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--from",
                     src_uuid,
                     "--to",
                     tgt_uuid,
                     "--yes"
                   ])
        end)

      assert output =~ "moved to"
    end

    test "--from/--to identical source and target UUIDs error before listing" do
      same_uuid = "00000000-0000-1000-8000-000000000001"
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        raise "no API call should be made for same-ID move; got: #{query}"
      end)

      capture_io(:stderr, fn ->
        LinearCli.CLI.main(
          ["issue", "move", "--from", same_uuid, "--to", same_uuid],
          halt
        )
      end)

      assert_received {:halted, 22}
    end

    test "--from/--to user declines prints 'Move cancelled'" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        case Enum.find(bulk_stub_pairs(), fn {match, _} -> String.contains?(query, match) end) do
          {_match, response} -> Req.Test.json(conn, response)
          nil -> raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io([input: "n\n"], fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "move",
                     "--from",
                     "Source Project",
                     "--to",
                     "Target Project",
                     "--team",
                     "ENG"
                   ])
        end)

      assert output =~ "Move cancelled"
    end

    test "--from without --to exits 22 with a clear error" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "move", "--from", "Source Project"], halt)
        end)

      assert_received {:halted, 22}
      assert output =~ "--from and --to must both be given"
    end

    test "--to without --from exits 22 with a clear error" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "move", "--to", "Target Project"], halt)
        end)

      assert_received {:halted, 22}
      assert output =~ "--from and --to must both be given"
    end
  end

  describe "issue comment" do
    defp stub_lookup_and(pairs) do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          match = Enum.find(pairs, fn {substr, _resp} -> String.contains?(query, substr) end) ->
            {_substr, resp} = match
            Req.Test.json(conn, (is_function(resp, 1) && resp.(decoded)) || resp)

          true ->
            raise "no stub matched query: #{query}"
        end
      end)
    end

    test "creates a new comment" do
      stub_lookup_and([{"commentCreate", comment_created()}])

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "comment", "CRY-1", "-m", "lgtm"])
        end)

      assert output =~ "Comment added to CRY-1"
    end

    test "--body-file reads the body from a file verbatim" do
      path = tmp_path("body_file")
      # Deliberately includes a literal backslash-n and a $VAR-looking string -
      # exactly the content that broke when built as an inline shell argument
      # (see documents/phase-13-plan.adoc's Goal section).
      File.write!(path, "## Investigation\n\nliteral \\n and $SOME_VAR survive verbatim")
      on_exit(fn -> File.rm(path) end)

      test_pid = self()

      stub_lookup_and([
        {"commentCreate",
         fn decoded ->
           send(test_pid, {:sent_body, decoded["variables"]["body"]})
           comment_created()
         end}
      ])

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "comment", "CRY-1", "--body-file", path])
      end)

      assert_received {:sent_body,
                       "## Investigation\n\nliteral \\n and $SOME_VAR survive verbatim"}
    end

    test "--body-file - reads the body from stdin verbatim" do
      test_pid = self()

      stub_lookup_and([
        {"commentCreate",
         fn decoded ->
           send(test_pid, {:sent_body, decoded["variables"]["body"]})
           comment_created()
         end}
      ])

      capture_io("piped from stdin\nwith a real newline", fn ->
        assert :ok = LinearCli.CLI.main(["issue", "comment", "CRY-1", "--body-file", "-"])
      end)

      assert_received {:sent_body, "piped from stdin\nwith a real newline"}
    end

    test "--comment and --body-file together is a smells_bad error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            ["issue", "comment", "CRY-1", "-m", "text", "--body-file", "somefile"],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "give --comment or --body-file, not both"
    end

    test "an unreadable --body-file surfaces an error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      capture_io(:stderr, fn ->
        LinearCli.CLI.main(
          ["issue", "comment", "CRY-1", "--body-file", "/nonexistent/path/does-not-exist"],
          halt
        )
      end)

      assert_received {:halted, _code}
    end

    test "--output json prints the resulting comment as JSON" do
      stub_lookup_and([{"commentCreate", comment_created()}])

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main(["issue", "comment", "CRY-1", "-m", "lgtm", "-o", "json"])
        end)

      assert %{"id" => "c1"} = Jason.decode!(output)
    end
  end
end
