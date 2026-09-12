defmodule LinearCli.CLI.Commands.Issues.MutationsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Commands.Issues.Mutations

  # Shared across "issue status" and "issue take with --status" describe blocks
  defp state_map(id, name, position, type) do
    %{"id" => id, "name" => name, "position" => position, "type" => type, "description" => nil}
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
        capture_io(:stderr, fn ->
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
            "update",
            "--body-file",
            "/nonexistent/path/does-not-exist",
            "CRY-1"
          ],
          halt
        )
      end)

      assert_received {:halted, _code}
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
        capture_io(:stderr, fn ->
          LinearCli.CLI.main(["issue", "comment", "-m", "lgtm"], halt)
        end)

      assert_received {:halted, 22}
      assert output =~ "No issue IDs provided!"
    end
  end
end
