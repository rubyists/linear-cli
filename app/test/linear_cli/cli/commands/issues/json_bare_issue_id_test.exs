defmodule LinearCli.CLI.Commands.Issues.JsonBareIssueIdTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Issue.Identifiers
  alias LinearCli.{Favorites, Profiles}

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)

    on_exit(fn -> File.rm(path) end)
    :ok
  end

  defp teams_response(teams) do
    %{
      "data" => %{
        "viewer" => %{
          "id" => "u1",
          "name" => "Ada",
          "email" => "ada@example.com",
          "teams" => %{"nodes" => teams}
        }
      }
    }
  end

  defp team_map(key, id) do
    %{"id" => id, "key" => key, "name" => key}
  end

  defp run_cli(argv, halt) do
    parent = self()

    stdout =
      capture_io(fn ->
        stderr =
          capture_stderr(fn stderr ->
            LinearCli.CLI.main(argv, halt, stderr: stderr)
          end)

        send(parent, {:captured_stderr, stderr})
      end)

    receive do
      {:captured_stderr, stderr} -> {stdout, stderr}
    after
      1_000 -> raise "did not receive captured stderr"
    end
  end

  test "issue move rejects an ambiguous favorite-team choice before any API call" do
    test_pid = self()
    Favorites.add("team", "ENG")
    Favorites.add("team", "SUP")

    Req.Test.stub(LinearCli.Api, fn conn ->
      send(test_pid, :api_called)
      Req.Test.json(conn, %{"data" => %{}})
    end)

    halt = fn code -> send(test_pid, {:halted, code}) end

    {stdout, stderr} =
      run_cli(
        ["issue", "move", "--project", "Manhattan", "--yes", "--output", "json", "42"],
        halt
      )

    assert stdout == ""
    assert stderr =~ "JSON output cannot prompt for a team"
    assert_received {:halted, 22}
    refute_received :api_called
  end

  test "issue unassign rejects an ambiguous available-team choice before any API call" do
    test_pid = self()

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)

      if String.contains?(query, "viewer") do
        Req.Test.json(conn, teams_response([team_map("ENG", "t1"), team_map("SUP", "t2")]))
      else
        send(test_pid, :api_called)
        Req.Test.json(conn, %{"data" => %{}})
      end
    end)

    halt = fn code -> send(test_pid, {:halted, code}) end
    {stdout, stderr} = run_cli(["issue", "unassign", "--output", "json", "42"], halt)

    assert stdout == ""
    assert stderr =~ "JSON output cannot prompt for a team"
    assert_received {:halted, 22}
    refute_received :api_called
  end

  test "issue move uses one favorite team in JSON mode without prompting" do
    test_pid = self()
    Favorites.add("team", "ENG")

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = decoded = Jason.decode!(body)

      cond do
        String.contains?(query, "issue(id: $id)") ->
          Req.Test.json(
            conn,
            %{
              "data" => %{
                "issue" =>
                  issue_map(%{
                    "identifier" => "ENG-42",
                    "team" => team_map("ENG", "t1")
                  })
              }
            }
          )

        String.contains?(query, "projects(first: 100") ->
          Req.Test.json(conn, team_projects([project_map("p1", "Manhattan")]))

        String.contains?(query, "issueUpdate") ->
          send(test_pid, {:mutation, decoded["variables"]["input"]["projectId"]})
          Req.Test.json(conn, issue_updated(%{"identifier" => "ENG-42"}))

        true ->
          raise "no stub matched query: #{query}"
      end
    end)

    {stdout, stderr} =
      run_cli(
        ["issue", "move", "--project", "Manhattan", "--yes", "--output", "json", "42"],
        fn _code ->
          flunk("one favorite team should not halt")
        end
      )

    assert {:ok, decoded} = Jason.decode(stdout)
    assert decoded["identifier"] == "ENG-42"
    assert stderr == ""
    assert_received {:mutation, "p1"}
  end

  test "active profile resolution also works in JSON mode without output" do
    {:ok, _profile} = Profiles.create("engineering", team: "ENG")
    :ok = Profiles.activate("engineering")

    assert capture_io(fn ->
             assert {:ok, "ENG-42"} = Identifiers.expand_issue_id("42", output: "json")
           end) == ""
  end
end
