defmodule LinearCli.CLI.Commands.Issues.MutationsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Commands.Issues.Mutations

  # Shared across "issue status" and "issue take with --status" describe blocks
  defp state_map(id, name, position, type) do
    %{"id" => id, "name" => name, "position" => position, "type" => type, "description" => nil}
  end

  defp assignee_members_response(members) do
    %{"data" => %{"team" => %{"members" => %{"nodes" => members}}}}
  end

  describe "issue unassign edge cases" do
    test "sends a null assignee and confirms each issue in text output" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:unassign_input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => nil}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "unassign", "CRY-1"])
        end)

      assert_received {:unassign_input, %{"assigneeId" => nil}}
      assert output =~ "CRY-1 unassigned"
    end

    test "returns a single issue object for JSON output" do
      stub_responses([
        {"issue(id: $id)", %{"data" => %{"issue" => issue_map()}}},
        {"issueUpdate", issue_updated(%{"assignee" => nil})}
      ])

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "unassign", "--output", "json", "CRY-1"])
        end)

      assert {:ok, decoded} = Jason.decode(output)
      assert decoded["identifier"] == "CRY-1"
      assert is_nil(decoded["assignee"])
    end

    test "updates multiple issue IDs concurrently and preserves JSON order" do
      test_pid = self()

      issue_details = fn
        "CRY-1" -> {"i1", "CRY-1"}
        "CRY-2" -> {"i2", "CRY-2"}
      end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]
        variables = decoded["variables"] || %{}

        cond do
          String.contains?(query, "issue(id: $id)") ->
            {_id, identifier} = issue_details.(variables["id"])

            Req.Test.json(conn, %{
              "data" => %{"issue" => issue_map(%{"identifier" => identifier})}
            })

          String.contains?(query, "issueUpdate") ->
            {_id, identifier} = issue_details.(variables["id"])
            assert variables["input"] == %{"assigneeId" => nil}
            update_pid = self()
            send(test_pid, {:unassign_started, identifier, update_pid})

            receive do
              :finish_unassign -> :ok
            after
              2_000 -> raise "unassign update was not released by the concurrency assertion"
            end

            Req.Test.json(
              conn,
              issue_updated(%{"identifier" => identifier, "assignee" => nil})
            )

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
                       "unassign",
                       "--output",
                       "json",
                       "CRY-1",
                       "CRY-2"
                     ])
          end)
        end)

      assert_receive {:unassign_started, "CRY-1", first_update}, 1_000
      assert_receive {:unassign_started, "CRY-2", second_update}, 1_000
      send(first_update, :finish_unassign)
      send(second_update, :finish_unassign)

      output = Task.await(command)
      assert {:ok, decoded} = Jason.decode(output)
      assert Enum.map(decoded, & &1["identifier"]) == ["CRY-1", "CRY-2"]
    end

    test "with no issue IDs or filter selector, exits 22" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(["issue", "unassign"], halt, stderr: stderr)
        end)

      assert_received {:halted, 22}
      assert output =~ "Provide issue IDs or at least one filter selector!"
    end

    test "filters by assignee and clears every matching issue" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              %{
                "data" => %{
                  "team" => %{
                    "members" => %{
                      "nodes" => [%{"id" => "u1", "name" => "Ada", "email" => "ada@example.com"}]
                    }
                  }
                }
              }
            )

          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "issues(filter:") ->
            send(test_pid, {:issue_filter, decoded["variables"]})
            Req.Test.json(conn, issues_response([issue_map(%{"assignee" => me_map()})]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:unassign_input, decoded["variables"]["input"]})
            Req.Test.json(conn, issue_updated(%{"assignee" => nil}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--assignee",
                     "Ada",
                     "--yes"
                   ])
        end)

      assert_received {:issue_filter, %{"filter" => filter, "first" => 50, "after" => nil}}
      assert filter["assignee"] == %{"id" => %{"eq" => "u1"}}
      refute get_in(filter, ["assignee", "isMe"])
      assert_received {:unassign_input, %{"assigneeId" => nil}}
      refute output =~ "Unassign 1 issue(s)?"
      assert output =~ "CRY-1 unassigned"
    end

    test "fetches all filtered pages before unassigning more than 100 matches" do
      test_pid = self()

      page_issues = fn first, last ->
        Enum.map(first..last, fn number ->
          issue_map(%{"id" => "i#{number}", "identifier" => "CRY-#{number}"})
        end)
      end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issues(filter:") ->
            cursor = decoded["variables"]["after"]
            send(test_pid, {:page_requested, cursor})

            page =
              case cursor do
                nil -> issues_response_page(page_issues.(1, 50), true, "c1")
                "c1" -> issues_response_page(page_issues.(51, 100), true, "c2")
                "c2" -> issues_response_page(page_issues.(101, 120), false, "c3")
              end

            Req.Test.json(conn, page)

          String.contains?(query, "issueUpdate") ->
            identifier = decoded["variables"]["id"]
            send(test_pid, {:updated, identifier})
            Req.Test.json(conn, issue_updated(%{"identifier" => identifier, "assignee" => nil}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--output",
                     "json",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--yes"
                   ])
        end)

      assert_received {:page_requested, nil}
      assert_received {:page_requested, "c1"}
      assert_received {:page_requested, "c2"}

      assert {:ok, updated} = Jason.decode(output)
      assert length(updated) == 120
      assert List.first(updated)["identifier"] == "CRY-1"
      assert List.last(updated)["identifier"] == "CRY-120"

      updated_ids =
        Enum.reduce(1..120, [], fn _number, acc ->
          receive do
            {:updated, identifier} -> [identifier | acc]
          after
            1_000 -> flunk("expected all 120 issue updates")
          end
        end)

      assert length(updated_ids) == 120
    end

    test "confirms the filtered batch and cancels without mutating" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = decoded = Jason.decode!(body)

        cond do
          String.contains?(query, "issues(filter:") ->
            Req.Test.json(conn, issues_response([issue_map()]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutated)
            raise "a declined filtered batch must not mutate"

          true ->
            raise "no stub matched query: #{inspect(decoded)}"
        end
      end)

      output =
        capture_io([input: "n\n"], fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--state",
                     "started"
                   ])
        end)

      refute_received :mutated
      assert output =~ "Unassign 1 issue(s)?"
      assert output =~ "Unassign cancelled"
    end

    test "--dry-run lists filtered matches without mutation" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issues(filter:") ->
            Req.Test.json(conn, issues_response([issue_map()]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutated)
            raise "--dry-run must not mutate"

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--state",
                     "started",
                     "--dry-run"
                   ])
        end)

      refute_received :mutated
      assert output =~ "CRY-1"
      assert output =~ "Would unassign 1 issue(s)"
    end

    test "--dry-run returns the selected issues as JSON without mutation" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "issues(filter:") ->
            Req.Test.json(conn, issues_response([issue_map()]))

          String.contains?(query, "issueUpdate") ->
            send(test_pid, :mutated)
            raise "--dry-run must not mutate"

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--output",
                     "json",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--state",
                     "started",
                     "--dry-run"
                   ])
        end)

      refute_received :mutated
      assert {:ok, decoded} = Jason.decode(output)
      assert decoded["identifier"] == "CRY-1"
    end

    test "shares team, state, status, and label filters with issue list" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "issues(filter:") do
          send(test_pid, {:issue_filter, decoded["variables"]["filter"]})
          Req.Test.json(conn, issues_response([]))
        else
          raise "unassign must not mutate an empty filtered result"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "unassign",
                   "--no-profile",
                   "--no-mine",
                   "--team",
                   "ENG",
                   "--state",
                   "started",
                   "--status",
                   "Human Review",
                   "--labels",
                   "Bug,Feature"
                 ])
      end)

      assert_received {:issue_filter, filter}
      assert filter["team"] == %{"key" => %{"eq" => "ENG"}}
      assert filter["state"]["type"] == %{"in" => ["started"]}
      assert filter["state"]["name"] == %{"eqIgnoreCase" => "Human Review"}

      assert filter["labels"] == %{
               "some" => %{
                 "or" => [
                   %{"name" => %{"eqIgnoreCase" => "Bug"}},
                   %{"name" => %{"eqIgnoreCase" => "Feature"}}
                 ]
               }
             }
    end

    test "reports no matches without sending an update" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]

        if String.contains?(query, "issues(filter:") do
          Req.Test.json(conn, issues_response([]))
        else
          raise "no update is expected when no issues match"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--no-profile",
                     "--team",
                     "ENG"
                   ])
        end)

      assert output =~ "No issues matched."
    end

    test "returns an empty JSON array for no matches" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]

        if String.contains?(query, "issues(filter:") do
          Req.Test.json(conn, issues_response([]))
        else
          raise "no update is expected when no issues match"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--output",
                     "json",
                     "--no-profile",
                     "--team",
                     "ENG"
                   ])
        end)

      assert {:ok, []} = Jason.decode(output)
    end

    test "rejects issue IDs combined with filter options before a GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn ->
        raise "the conflicting invocation must not make a GraphQL call"
      end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "unassign", "--team", "ENG", "--no-profile", "CRY-1"],
            halt,
            stderr: stderr
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "Issue IDs cannot be combined with filter options!"
    end

    test "fails safely when the requested project does not resolve" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]

        if String.contains?(query, "projects(first: $first") do
          Req.Test.json(conn, all_projects([]))
        else
          raise "a missing project must stop before the issue query"
        end
      end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "unassign", "--no-profile", "--project", "Missing Project"],
            halt,
            stderr: stderr
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "No project found matching Missing Project"
    end

    test "prompts for a partial project match before filtering" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)

        cond do
          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, team_projects([project_map("p1", "Roadmap Q4")]))

          String.contains?(query, "issues(filter:") ->
            Req.Test.json(conn, issues_response([]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io([input: "1\n"], fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--project",
                     "Roadmap",
                     "--dry-run"
                   ])
        end)

      assert output =~ "Project:"
      assert output =~ "No issues matched."
    end

    test "prompts for a partial assignee match and filters by the selected ID" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = decoded = Jason.decode!(body)

        cond do
          String.contains?(query, "members(first: 50)") ->
            Req.Test.json(
              conn,
              assignee_members_response([
                %{"id" => "u1", "name" => "Alice Smith", "displayName" => "alice"},
                %{"id" => "u2", "name" => "Alina Jones", "displayName" => "alina"}
              ])
            )

          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "issues(filter:") ->
            send(test_pid, {:filter, decoded["variables"]["filter"]})
            Req.Test.json(conn, issues_response([]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io([input: "1\n"], fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "unassign",
                     "--no-profile",
                     "--team",
                     "ENG",
                     "--assignee",
                     "Ali",
                     "--dry-run"
                   ])
        end)

      assert output =~ "Assignee:"
      assert output =~ "No issues matched."
      assert_received {:filter, filter}
      assert filter["assignee"] == %{"id" => %{"eq" => "u1"}}
    end

    test "fetches every page before starting updates" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issues(filter:") ->
            case decoded["variables"]["after"] do
              nil -> Req.Test.json(conn, issues_response_page([issue_map()], true, "c1"))
              "c1" -> Plug.Conn.resp(conn, 502, "upstream unavailable")
            end

          String.contains?(query, "issueUpdate") ->
            raise "no update is allowed after a later-page read error"

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "unassign", "--no-profile", "--team", "ENG"],
            halt,
            stderr: stderr
          )
        end)

      assert_received {:halted, 88}
      assert output =~ "Cannot Continue"
    end

    test "rejects unrecognized options before making a GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn ->
        raise "unassign must reject the option before making a GraphQL call"
      end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "unassign", "--statuz", "CRY-1"],
            halt,
            stderr: stderr
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "unrecognized option(s): --statuz"
    end

    test "an unknown issue ID exits 66" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"data" => %{"issue" => nil}})
      end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(["issue", "unassign", "CRY-999"], halt, stderr: stderr)
        end)

      assert_received {:halted, 66}
      assert output =~ "No issue found with id CRY-999"
    end

    test "preserves the generic mutation-error catch-all and exit 88" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]

        if String.contains?(query, "issue(id: $id)") do
          Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})
        else
          Req.Test.json(conn, %{"errors" => [%{"message" => "mutation denied"}]})
        end
      end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(["issue", "unassign", "CRY-1"], halt, stderr: stderr)
        end)

      assert_received {:halted, 88}
      assert output =~ "What the heck is this? ** (Ash.Error.Invalid)"
      assert output =~ "** WTH? Cannot Continue **"
      refute output =~ "mutation denied"
    end
  end

  describe "issue status" do
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "status", "--statuz", "Done", "CRY-1", "CRY-2"],
            halt,
            stderr: stderr
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "status", "--status", "Nonexistent", "CRY-1"],
            halt,
            stderr: stderr
          )
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "status", "--status", "Do", "CRY-1"],
            halt,
            stderr: stderr
          )
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(["issue", "update"], halt, stderr: stderr)
        end)

      assert_received {:halted, 22}
      assert output =~ "No issue IDs provided!"
      assert output =~ "This smells bad! Bailing."
    end

    test "--body-file reads the description from a file verbatim" do
      path = tmp_path("body_file")
      File.write!(path, "## Summary\n\nliteral \\n and $SOME_VAR survive verbatim")
      on_exit(fn -> File.rm(path) end)

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

            Req.Test.json(
              conn,
              issue_updated(%{
                "description" => "## Summary\n\nliteral \\n and $SOME_VAR survive verbatim"
              })
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
                     "update",
                     "--body-file",
                     path,
                     "CRY-1"
                   ])
        end)

      assert_received {:description, "## Summary\n\nliteral \\n and $SOME_VAR survive verbatim"}
      assert output =~ "CRY-1 description updated"
    end

    test "--body-file - reads the description from stdin" do
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
            Req.Test.json(conn, issue_updated(%{"description" => "from stdin body"}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        unknown: ["CRY-1"],
        options: %{
          body_file: "-",
          description: nil,
          comment: nil,
          project: nil,
          reason: nil,
          status: nil
        },
        flags: %{cancel: false, close: false, trash: false}
      }

      capture_io("from stdin body", fn ->
        assert :ok = Mutations.issue_update(result)
      end)

      assert_received {:description, "from stdin body"}
    end

    test "--description and --body-file together is a smells_bad error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            [
              "issue",
              "update",
              "-d",
              "some desc",
              "--body-file",
              "somefile",
              "CRY-1"
            ],
            halt,
            stderr: stderr
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "give --description or --body-file, not both"
    end

    test "an unreadable --body-file surfaces an error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      capture_stderr(fn stderr ->
        LinearCli.CLI.main(
          [
            "issue",
            "update",
            "--body-file",
            "/nonexistent/path/does-not-exist",
            "CRY-1"
          ],
          halt,
          stderr: stderr
        )
      end)

      assert_received {:halted, _code}
    end
  end

  describe "issue update --priority" do
    test "--priority high sends priority: 2 in the mutation input" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:priority, decoded["variables"]["input"]["priority"]})
            Req.Test.json(conn, issue_updated(%{"priority" => 2.0, "priorityLabel" => "High"}))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "update", "--priority", "high", "CRY-1"])
        end)

      assert_received {:priority, 2}
      assert output =~ "CRY-1 priority updated"
    end

    test "--priority none sends priority: 0 to clear it" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:priority, decoded["variables"]["input"]["priority"]})

            Req.Test.json(
              conn,
              issue_updated(%{"priority" => 0.0, "priorityLabel" => "No priority"})
            )

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "update", "--priority", "none", "CRY-1"])
        end)

      assert_received {:priority, 0}
      assert output =~ "CRY-1 priority updated"
    end

    test "--priority is case-insensitive (URGENT maps to 1)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:priority, decoded["variables"]["input"]["priority"]})
            Req.Test.json(conn, issue_updated())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "update", "--priority", "URGENT", "CRY-1"])
      end)

      assert_received {:priority, 1}
    end

    test "--priority with unknown value exits 22 without calling issueUpdate" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      stderr =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "update", "--priority", "critical", "CRY-1"], halt)
        end)

      assert_received {:halted, 22}
      assert stderr =~ "critical"
      assert stderr =~ "none, urgent, high, medium, low"
    end

    test "--priority with multiple issue IDs updates each" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            id = decoded["variables"]["id"]
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map(%{"identifier" => id})}})

          String.contains?(query, "issueUpdate") ->
            id = decoded["variables"]["id"]
            send(test_pid, {:updated, id})
            Req.Test.json(conn, issue_updated())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "update",
                   "--priority",
                   "low",
                   "CRY-1",
                   "CRY-2"
                 ])
      end)

      assert_received {:updated, "CRY-1"}
      assert_received {:updated, "CRY-2"}
    end

    test "--output json still updates priority and confirms via stdout" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        query = Jason.decode!(body)["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, issue_updated(%{"priority" => 3.0, "priorityLabel" => "Medium"}))

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
                     "--priority",
                     "medium",
                     "--output",
                     "json",
                     "CRY-1"
                   ])
        end)

      assert output =~ "CRY-1 priority updated"
    end

    test "--priority combined with --comment posts comment first then updates priority" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "commentCreate") ->
            send(test_pid, :comment_created)
            Req.Test.json(conn, comment_created())

          String.contains?(query, "issueUpdate") ->
            send(test_pid, {:priority, decoded["variables"]["input"]["priority"]})
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
                     "--priority",
                     "high",
                     "--comment",
                     "bumping priority",
                     "CRY-1"
                   ])
        end)

      assert_received :comment_created
      assert_received {:priority, 2}
      assert output =~ "Comment added to CRY-1"
      assert output =~ "CRY-1 priority updated"
    end

    test "all documented priority names map to their correct integer values" do
      priorities = [
        {"none", 0},
        {"urgent", 1},
        {"high", 2},
        {"medium", 3},
        {"low", 4}
      ]

      for {name, expected_int} <- priorities do
        test_pid = self()

        Req.Test.stub(LinearCli.Api, fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          query = decoded["query"]

          cond do
            String.contains?(query, "issue(id: $id)") ->
              Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

            String.contains?(query, "issueUpdate") ->
              send(test_pid, {:priority, decoded["variables"]["input"]["priority"]})
              Req.Test.json(conn, issue_updated())

            true ->
              raise "no stub matched query: #{query}"
          end
        end)

        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main(["issue", "update", "--priority", name, "CRY-1"]),
                 "expected #{name} to succeed"
        end)

        assert_received {:priority, ^expected_int}, "expected #{name} => #{expected_int}"
      end
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "assign", "--assignee", "Nobody", "CRY-1"],
            halt,
            stderr: stderr
          )
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "assign", "--assignee", "Bo", "CRY-1"],
            halt,
            stderr: stderr
          )
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(["issue", "assign", "CRY-1"], halt, stderr: stderr)
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "assign", "-a", "Bob", "--status", "NoSuchState", "CRY-1"],
            halt,
            stderr: stderr
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "take", "--status", "Bogus", "CRY-1"],
            halt,
            stderr: stderr
          )
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
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(
            ["issue", "comment", "CRY-1", "-m", "text", "--body-file", "somefile"],
            halt,
            stderr: stderr
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "give --comment or --body-file, not both"
    end

    test "an unreadable --body-file surfaces an error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      capture_stderr(fn stderr ->
        LinearCli.CLI.main(
          ["issue", "comment", "CRY-1", "--body-file", "/nonexistent/path/does-not-exist"],
          halt,
          stderr: stderr
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

    test "multiple ISSUE_IDs each receive the comment" do
      test_pid = self()

      stub_lookup_and([
        {"commentCreate",
         fn _decoded ->
           send(test_pid, :comment_created)
           comment_created()
         end}
      ])

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main(["issue", "comment", "CRY-1", "CRY-2", "-m", "lgtm"])
        end)

      assert output =~ "Comment added to"
      assert_received :comment_created
      assert_received :comment_created
    end

    test "no ISSUE_IDs is a smells_bad error" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_stderr(fn stderr ->
          LinearCli.CLI.main(["issue", "comment", "-m", "lgtm"], halt, stderr: stderr)
        end)

      assert_received {:halted, 22}
      assert output =~ "No issue IDs provided!"
    end
  end
end
