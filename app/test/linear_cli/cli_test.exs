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

  test "project update resolves the project by name and posts a status update" do
    test_pid = self()

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      query = decoded["query"]

      cond do
        String.contains?(query, "projects(first: $first") ->
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
                    "cursor" => "p1"
                  }
                ],
                "pageInfo" => %{"hasNextPage" => false}
              }
            }
          })

        String.contains?(query, "projectUpdateCreate") ->
          send(test_pid, {:input, decoded["variables"]["input"]})

          Req.Test.json(conn, %{
            "data" => %{
              "projectUpdateCreate" => %{
                "projectUpdate" => %{
                  "id" => "pu1",
                  "body" => "Doing great",
                  "health" => "onTrack",
                  "url" => "https://linear.app/x/update/pu1"
                }
              }
            }
          })

        true ->
          raise "no stub matched query: #{query}"
      end
    end)

    output =
      capture_io(fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "project",
                   "update",
                   "Manhattan",
                   "--body",
                   "Doing great",
                   "--health",
                   "onTrack"
                 ])
      end)

    assert output =~ "onTrack"
    assert output =~ "https://linear.app/x/update/pu1"

    assert_received {:input,
                     %{"projectId" => "p1", "body" => "Doing great", "health" => "onTrack"}}
  end

  test "issue list prints a one-line summary per issue" do
    assert capture_io(fn -> LinearCli.CLI.main(["issue", "list"]) end) =~ "CRY-1"
  end

  test "issue list --help shows subcommand help instead of treating --help as an issue id" do
    # --help makes Optimus print help and halt (its own internal halt call,
    # now wired to ours) - inject a no-op halt so this doesn't kill the test
    # VM. Optimus.parse!/3 assumes halt never returns; with a fake one it
    # returns :ok instead of {subcommand_path, parse_result} (or a bare
    # %Optimus.ParseResult{}), which blows up main/1's own case statement -
    # a CaseClauseError. Real usage never hits that (real halt terminates
    # the process) - it's only an artifact of faking halt here, so rescue it
    # rather than treat it as a failure.
    output =
      capture_io(fn ->
        try do
          LinearCli.CLI.main(["issue", "list", "--help"], fn _code -> :ok end)
        rescue
          CaseClauseError -> :ok
        end
      end)

    assert output =~ "List issues"
    refute output =~ "CRY-1"
  end

  test "issue list --mine gives a clear error instead of being treated as an issue id (#2)" do
    # `--mine` isn't (and won't be - `--no-mine` already covers it, `--mine`
    # is the implied default) a declared flag on `issue list`. Since this
    # subcommand allows unknown args (for bare issue ids), an unrecognized
    # `-`-prefixed token used to silently fall into that same bucket and get
    # looked up as a literal issue id "--mine" instead of erroring - crashing
    # with a raw %Ash.Error.Unknown{} dump. No Req.Test stub needed: the fix
    # rejects this before any API call happens.
    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output =
      capture_io(:stderr, fn ->
        LinearCli.CLI.main(["issue", "list", "--mine"], halt)
      end)

    assert_received {:halted, 22}
    assert output =~ "unrecognized option(s): --mine"
    assert output =~ "This smells bad! Bailing."
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

  test "version -o json prints valid JSON with the version field" do
    version = to_string(Application.spec(:linear_cli, :vsn))
    output = capture_io(fn -> LinearCli.CLI.main(["version", "-o", "json"]) end)
    assert %{"version" => ^version} = Jason.decode!(output)
  end

  test "--develop and --butwhy are rewritten to their canonical --dev/--reason spellings" do
    # Ruby's create.rb declares `--dev` with alias `--develop`, and update.rb's
    # `--reason` has alias `--butwhy` - both real, user-facing spellings.
    # Optimus flags/options support exactly one `long:` name each (no alias
    # mechanism), so LinearCli.CLI rewrites the secondary spelling itself
    # before Optimus ever parses it. Testing the rewrite directly (rather
    # than driving a full `issue create`/`issue update` flow through
    # main/1) avoids having to stub an entire interactive prompt chain just
    # to prove an argv token got renamed.
    assert LinearCli.CLI.normalize_aliases(["issue", "create", "--develop"]) ==
             ["issue", "create", "--dev"]

    assert LinearCli.CLI.normalize_aliases(["issue", "update", "CRY-1", "--butwhy", "x"]) ==
             ["issue", "update", "CRY-1", "--reason", "x"]

    assert LinearCli.CLI.normalize_aliases(["whoami"]) == ["whoami"]
  end

  test "subcommand aliases (#14) rewrite to their canonical top-level/subcommand names" do
    # Sourced from Ruby's own ALIASES constants (cli.rb/commands/*.rb), not
    # the Readme's prose list. Direct unit tests on the pure rewrite, same
    # rationale as the flag-alias test above.
    assert LinearCli.CLI.normalize_subcommand_aliases(["i", "dev", "CRY-37"]) ==
             ["issue", "develop", "CRY-37"]

    assert LinearCli.CLI.normalize_subcommand_aliases(["issues", "l"]) == ["issue", "list"]
    assert LinearCli.CLI.normalize_subcommand_aliases(["t", "ls"]) == ["team", "list"]
    assert LinearCli.CLI.normalize_subcommand_aliases(["p", "l"]) == ["project", "list"]
    assert LinearCli.CLI.normalize_subcommand_aliases(["w", "-t"]) == ["whoami", "-t"]
    assert LinearCli.CLI.normalize_subcommand_aliases(["v"]) == ["version"]

    assert LinearCli.CLI.normalize_subcommand_aliases(["i", "pull-request", "CRY-1"]) ==
             ["issue", "pr", "CRY-1"]

    # `take` has no alias in Ruby either - unaliased subcommands pass through.
    assert LinearCli.CLI.normalize_subcommand_aliases(["issue", "take", "CRY-1"]) ==
             ["issue", "take", "CRY-1"]

    assert LinearCli.CLI.normalize_subcommand_aliases([]) == []
  end

  test "aliased subcommands actually dispatch end to end" do
    assert capture_io(fn -> LinearCli.CLI.main(["w"]) end) =~ "Ada"
    assert capture_io(fn -> LinearCli.CLI.main(["i", "ls"]) end) =~ "CRY-1"
    assert capture_io(fn -> LinearCli.CLI.main(["t", "l"]) end) =~ "Engineering"
    assert capture_io(fn -> LinearCli.CLI.main(["p", "ls"]) end) =~ "Manhattan"
  end

  test "an aliased subcommand composes correctly with --help" do
    # normalize_subcommand_aliases/1 has to run before normalize_help/1 -
    # Optimus's `help <path>` only recognizes canonical subcommand names,
    # not aliases, so "i dev --help" must become "help issue develop", not
    # a broken "help i dev". Same fake-halt/CaseClauseError artifact as the
    # "issue list --help" test above.
    output =
      capture_io(fn ->
        try do
          LinearCli.CLI.main(["i", "dev", "--help"], fn _code -> :ok end)
        rescue
          CaseClauseError -> :ok
        end
      end)

    assert output =~ "Start or update development status of an issue"
  end

  test "a catch-all error halts with exit code 88" do
    # A malformed API response (neither "data" nor "errors") makes
    # LinearCli.Api return {:error, {:unexpected_response, body}}, which Ash
    # wraps into a generic %Ash.Error.Unknown{} matching neither the
    # not-found nor smells_bad handle_error/3 clauses - it should fall
    # through to the catch-all. This module is async: true, so (unlike an
    # env-var-based approach, which would race with every other
    # concurrently-running test file that needs LINEAR_API_KEY present -
    # exactly the class of bug this codebase already hit and fixed once)
    # a stubbed response is the safe way to trigger this path.
    Req.Test.stub(LinearCli.Api, fn conn -> Req.Test.json(conn, %{"wat" => true}) end)

    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output =
      capture_io(:stderr, fn ->
        LinearCli.CLI.main(["whoami"], halt)
      end)

    assert_received {:halted, 88}
    assert output =~ "What the heck is this?"
    assert output =~ "** WTH? Cannot Continue **"
  end

  test "a bare parent command (no leaf subcommand) shows that path's help and exits 1" do
    # `lc project` with nothing after it is a valid Optimus subcommand path
    # (Optimus doesn't require reaching a leaf) but dispatch/3 previously had
    # no clause for it at all, raising a bare FunctionClauseError instead of
    # showing help - a real crash a user could easily trigger by just
    # forgetting the subcommand.
    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output = capture_io(fn -> LinearCli.CLI.main(["project"], halt) end)

    assert_received {:halted, 1}
    assert output =~ "Manage projects"
    assert output =~ "List projects"
  end

  test "an unexpected raise (not a returned error) still degrades to exit 88, not a raw crash" do
    # A malformed API response (no "viewer" key at all) makes the manual
    # read return {:ok, %{}} instead of {:ok, [records]}, which Ash's own
    # manual-action-return validation *raises* on - a genuine exception, not
    # a {:error, reason} tuple. run/3's handle_error/3 only ever sees
    # returned values; this proves the main/1-level rescue (Ruby's
    # Caller#call had a blanket `rescue StandardError` - ours previously
    # only caught returned errors, not actual crashes) catches real bugs
    # too, not just this one known case.
    Req.Test.stub(LinearCli.Api, fn conn -> Req.Test.json(conn, %{"data" => %{}}) end)

    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output = capture_io(:stderr, fn -> LinearCli.CLI.main(["whoami"], halt) end)

    assert_received {:halted, 88}
    assert output =~ "What the heck is this?"
  end

  test "project list --team fetches a team's projects directly" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query, "variables" => variables} = Jason.decode!(body)

      cond do
        query =~ "team(id: $id)" ->
          assert variables == %{"id" => "ENG"}

          Req.Test.json(conn, %{
            "data" => %{"team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}}
          })

        query =~ "team(id: $teamId)" ->
          assert variables == %{"teamId" => "t1"}

          Req.Test.json(conn, %{
            "data" => %{
              "team" => %{
                "projects" => %{
                  "nodes" => [%{"id" => "p2", "name" => "Roadmap", "url" => "https://x/p2"}]
                }
              }
            }
          })
      end
    end)

    assert capture_io(fn -> LinearCli.CLI.main(["project", "list", "--team", "ENG"]) end) =~
             "Roadmap"
  end

  test "project list --team with an unknown team key gives a clear not-found message, not WTH" do
    # find_team/1's get?: true action returns Ash's own built-in
    # %Ash.Error.Query.NotFound{} when the API responds with a nil team - a
    # different shape than Issue's {:not_found, id} tuple convention, so it
    # needs its own handle_error/3 clause (generic over `resource`, not
    # hardcoded to Team) rather than falling through to the "What the heck
    # is this?" catch-all.
    Req.Test.stub(LinearCli.Api, fn conn -> Req.Test.json(conn, %{"data" => %{"team" => nil}}) end)

    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output =
      capture_io(:stderr, fn ->
        LinearCli.CLI.main(["project", "list", "--team", "NOPE"], halt)
      end)

    assert_received {:halted, 66}
    assert output =~ "No such team found"
    refute output =~ "What the heck is this?"
  end
end
