defmodule LinearCli.CLITest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  setup do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)
      respond(conn, query)
    end)

    :ok
  end

  defp respond(conn, query) do
    cond do
      query =~ "viewer" ->
        Req.Test.json(conn, %{
          "data" => %{
            "viewer" => %{
              "id" => "u1",
              "name" => "Ada",
              "email" => "ada@example.com",
              "teams" => %{"nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]}
            }
          }
        })

      query =~ "teams(" ->
        Req.Test.json(conn, %{
          "data" => %{
            "teams" => %{
              "edges" => [
                %{"node" => %{"id" => "t2", "key" => "OPS", "name" => "Ops"}, "cursor" => "c1"}
              ],
              "pageInfo" => %{"hasNextPage" => false}
            }
          }
        })

      query =~ "projects(" ->
        Req.Test.json(conn, %{
          "data" => %{
            "projects" => %{
              "edges" => [
                %{
                  "node" => %{
                    "id" => "p1",
                    "name" => "Manhattan",
                    "slugId" => "abc",
                    "url" => "https://linear.app/x/project/manhattan-abc"
                  },
                  "cursor" => "c1"
                }
              ],
              "pageInfo" => %{"hasNextPage" => false}
            }
          }
        })

      query =~ "issues(" ->
        Req.Test.json(conn, %{
          "data" => %{
            "issues" => %{
              "edges" => [
                %{
                  "node" => %{
                    "id" => "i1",
                    "identifier" => "CRY-1",
                    "title" => "Fix the thing",
                    "assignee" => nil,
                    "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
                  },
                  "cursor" => "c1"
                }
              ],
              "pageInfo" => %{"hasNextPage" => false}
            }
          }
        })

      query =~ "issue(id:" ->
        Req.Test.json(conn, %{"data" => %{"issue" => nil}})
    end
  end

  test "whoami prints the user, and --teams appends the team list" do
    assert capture_io(fn -> LinearCli.CLI.main(["whoami"]) end) =~ "Ada"
    assert capture_io(fn -> LinearCli.CLI.main(["whoami", "-t"]) end) =~ "(Engineering)"
  end

  test "whoami -o json prints valid JSON with the expected fields" do
    output = capture_io(fn -> LinearCli.CLI.main(["whoami", "-o", "json"]) end)
    assert %{"name" => "Ada", "email" => "ada@example.com"} = Jason.decode!(output)
  end

  test "team list defaults to the caller's own teams (Ruby: --mine defaults true)" do
    assert capture_io(fn -> LinearCli.CLI.main(["team", "list"]) end) =~ "Engineering"
  end

  test "team list --no-mine lists all teams" do
    assert capture_io(fn -> LinearCli.CLI.main(["team", "list", "--no-mine"]) end) =~ "Ops"
  end

  test "project list defaults to all projects (Ruby: --mine defaults false)" do
    assert capture_io(fn -> LinearCli.CLI.main(["project", "list"]) end) =~ "Manhattan"
  end

  test "issue list prints a one-line summary per issue" do
    assert capture_io(fn -> LinearCli.CLI.main(["issue", "list"]) end) =~ "CRY-1"
  end

  test "issue list --help shows subcommand help instead of treating --help as an issue id" do
    # --help makes Optimus print help and halt (its own internal halt call,
    # now wired to ours) - inject a no-op halt so this doesn't kill the test
    # VM. Optimus.parse!/3 assumes halt never returns; with a fake one it
    # returns :ok instead of {subcommand_path, parse_result}, which blows up
    # our pattern match in main/1. Real usage never hits that MatchError
    # (real halt terminates the process) - it's only an artifact of faking
    # halt here, so rescue it rather than treat it as a failure.
    output =
      capture_io(fn ->
        try do
          LinearCli.CLI.main(["issue", "list", "--help"], fn _code -> :ok end)
        rescue
          MatchError -> :ok
        end
      end)

    assert output =~ "List issues"
    refute output =~ "CRY-1"
  end

  test "an unknown issue id halts with exit code 66" do
    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output =
      capture_io(:stderr, fn ->
        LinearCli.CLI.main(["issue", "list", "nope"], halt)
      end)

    assert_received {:halted, 66}
    assert output =~ "No issue found with id nope"
  end

  test "version prints the app version" do
    version = to_string(Application.spec(:linear_cli, :vsn))
    assert capture_io(fn -> LinearCli.CLI.main(["version"]) end) =~ version
  end
end
