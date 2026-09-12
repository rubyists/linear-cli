defmodule LinearCli.CLI.Commands.Issues.CreateTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Commands.Issues.Create
  alias LinearCli.Linear.User

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
        flags: %{develop: true, yes: false}
      }

      output =
        capture_io([input: "n\n"], fn ->
          assert :ok = Create.issue_create(result, cwd: repo, me: me)
        end)

      assert output =~ "Checked out branch cry-2-new-thing"
      assert output =~ "Upstream branch not found, pushing local cry-2-new-thing to origin"
      assert output =~ "Set upstream to origin/cry-2-new-thing"
      assert output =~ "Ready to develop!"
    end

    test "--body-file reads the description from a file verbatim" do
      path = tmp_path("body_file")
      # Includes a literal backslash-n and a $VAR-looking string — the same
      # content that broke when built as an inline shell argument (EXT-17 incident).
      File.write!(path, "## Summary\n\nliteral \\n and $SOME_VAR survive verbatim")
      on_exit(fn -> File.rm(path) end)

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "issueLabels") ->
            Req.Test.json(conn, label_response(["docs"]))

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, team_projects([]))

          String.contains?(query, "issueCreate") ->
            send(test_pid, {:sent_description, decoded["variables"]["input"]["description"]})

            Req.Test.json(conn, %{
              "data" => %{
                "issueCreate" => %{
                  "issue" => issue_map(%{"identifier" => "CRY-2", "title" => "T"})
                }
              }
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io([input: "n\n"], fn ->
        assert :ok =
                 LinearCli.CLI.main([
                   "issue",
                   "create",
                   "--body-file",
                   path,
                   "--title",
                   "T",
                   "--team",
                   "ENG",
                   "-l",
                   "docs"
                 ])
      end)

      assert_received {:sent_description,
                       "## Summary\n\nliteral \\n and $SOME_VAR survive verbatim"}
    end

    test "--body-file - reads the description from stdin" do
      # Uses Create.issue_create directly so that IO.read(:stdio, :eof) only
      # consumes the piped content (not the yes/no prompt input too). The
      # maybe_take prompt gets EOF after stdin is consumed; Owl.IO.confirm with
      # default: true returns true, so gimme_da_issue! runs and finds the issue
      # already assigned to `me`, short-circuiting without a second mutation.
      test_pid = self()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "issueLabels") ->
            Req.Test.json(conn, label_response([]))

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, team_projects([]))

          String.contains?(query, "issueCreate") ->
            send(test_pid, {:sent_description, decoded["variables"]["input"]["description"]})

            Req.Test.json(conn, %{
              "data" => %{
                "issueCreate" => %{
                  "issue" => issue_map(%{"id" => "i2", "identifier" => "CRY-2", "title" => "T"})
                }
              }
            })

          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{
              "data" => %{
                "issue" =>
                  issue_map(%{"id" => "i2", "identifier" => "CRY-2", "assignee" => me_map()})
              }
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        options: %{
          title: "T",
          body_file: "-",
          description: nil,
          team: "ENG",
          labels: [],
          project: nil,
          output: "text"
        },
        flags: %{develop: false, yes: false}
      }

      capture_io("piped from stdin\nwith a real newline", fn ->
        assert :ok = Create.issue_create(result, me: me)
      end)

      assert_received {:sent_description, "piped from stdin\nwith a real newline"}
    end

    test "--description and --body-file together is a smells_bad error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            [
              "issue",
              "create",
              "--title",
              "T",
              "--team",
              "ENG",
              "-d",
              "some desc",
              "--body-file",
              "somefile"
            ],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "give --description or --body-file, not both"
    end

    test "an unreadable --body-file surfaces an error, no GraphQL call" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      capture_io(:stderr, fn ->
        LinearCli.CLI.main(
          [
            "issue",
            "create",
            "--body-file",
            "/nonexistent/path/does-not-exist",
            "--title",
            "T",
            "--team",
            "ENG"
          ],
          halt
        )
      end)

      assert_received {:halted, _code}
    end

    test "--no-take keeps a -y/--yes-created issue unassigned" do
      created_issue =
        issue_map(%{
          "id" => "i2",
          "identifier" => "CRY-2",
          "title" => "New thing",
          "branchName" => "cry-2-new-thing",
          "description" => "Some description",
          "assignee" => nil
        })

      stub_responses([
        {"team(id: $id)", %{"data" => %{"team" => team_map()}}},
        {"projects(first: 100", team_projects([])},
        {"issueCreate", %{"data" => %{"issueCreate" => %{"issue" => created_issue}}}}
      ])

      output =
        capture_io(fn ->
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
                     "--yes",
                     "--no-take"
                   ])
        end)

      refute output =~ "Do you want to take this issue?"
      refute output =~ "Assigning issue"
      assert output =~ "CRY-2"
    end

    test "--no-take cannot be combined with --dev" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            [
              "issue",
              "create",
              "--title",
              "New thing",
              "--description",
              "Some description",
              "--team",
              "ENG",
              "--yes",
              "--no-take",
              "--dev"
            ],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "--no-take cannot be used with --dev"
    end

    test "-y/--yes with all required flags creates and self-assigns without any prompts" do
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
        {"projects(first: 100", team_projects([project_map("p1", "Manhattan Rollout")])},
        {"issueCreate", %{"data" => %{"issueCreate" => %{"issue" => created_issue}}}},
        {"viewer", %{"data" => %{"viewer" => me_map()}}},
        {"issue(id: $id)", %{"data" => %{"issue" => created_issue}}}
      ])

      output =
        capture_io(fn ->
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
                     "--project",
                     "Manhattan Rollout",
                     "--yes"
                   ])
        end)

      refute output =~ "Do you want to take this issue?"
      assert output =~ "CRY-2"
    end

    test "-y without --title is a smells_bad error" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            ["issue", "create", "--description", "Some desc", "--team", "ENG", "--yes"],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "--title is required with --yes"
    end

    test "-y without --description (or --body-file) is a smells_bad error" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            ["issue", "create", "--title", "New thing", "--team", "ENG", "--yes"],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "--description is required with --yes"
    end

    test "-y without --team (and multiple teams) is a smells_bad error" do
      test_pid = self()
      halt = fn code -> send(test_pid, {:halted, code}) end

      stub_responses([
        {"viewer",
         %{
           "data" => %{
             "viewer" => %{
               "id" => "u1",
               "name" => "Ada",
               "email" => "ada@x.com",
               "teams" => %{
                 "nodes" => [
                   team_map(),
                   %{"id" => "t2", "key" => "OPS", "name" => "Ops", "description" => nil}
                 ]
               }
             }
           }
         }}
      ])

      output =
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(
            [
              "issue",
              "create",
              "--title",
              "New thing",
              "--description",
              "Some desc",
              "--yes"
            ],
            halt
          )
        end)

      assert_received {:halted, 22}
      assert output =~ "--team is required"
    end

    test "-y with --project resolves it by exact match and uses it" do
      test_pid = self()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      created_issue =
        issue_map(%{
          "id" => "i2",
          "identifier" => "CRY-2",
          "title" => "T",
          "description" => "D",
          "assignee" => me_map()
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map()}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(
              conn,
              team_projects([
                project_map("p1", "Manhattan Rollout"),
                project_map("p2", "Other Project")
              ])
            )

          String.contains?(query, "issueCreate") ->
            send(test_pid, {:project_id, decoded["variables"]["input"]["projectId"]})
            Req.Test.json(conn, %{"data" => %{"issueCreate" => %{"issue" => created_issue}}})

          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"issue" => created_issue}})

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        assert :ok =
                 Create.issue_create(
                   %{
                     options: %{
                       title: "T",
                       description: "D",
                       team: "ENG",
                       labels: [],
                       project: "Manhattan Rollout",
                       output: "text"
                     },
                     flags: %{develop: false, yes: true}
                   },
                   me: me
                 )
      end)

      assert_received {:project_id, "p1"}
    end
  end
end
