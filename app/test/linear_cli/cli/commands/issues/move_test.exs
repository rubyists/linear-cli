defmodule LinearCli.CLI.Commands.Issues.MoveTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

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
end
