defmodule LinearCli.CLI.Commands.Issues.ReadTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Commands.Issues.Read

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
      # The production halt function never returns. Throw from the test double
      # too, so the parser's error path stops before it reaches the normal CLI
      # dispatch and emits an unrelated exception diagnostic.
      output =
        capture_io(fn ->
          assert catch_throw(
                   LinearCli.CLI.main(
                     ["issue", "list", "--state", "badtype"],
                     fn code -> throw({:halted, code}) end
                   )
                 ) == {:halted, 1}
        end)

      assert output =~ "invalid value \"badtype\" for --state option"
    end

    test "--labels filters by a single label name (case-insensitive)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--labels", "Incident-followup"])
      end)

      assert_received {:filter, filter}

      assert filter["labels"] == %{
               "some" => %{"name" => %{"eqIgnoreCase" => "Incident-followup"}}
             }
    end

    test "--labels accepts comma-separated names and matches issues with any of them (OR)" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([issue_map()]))
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--labels", "Bug,Feature"])
      end)

      assert_received {:filter, filter}

      assert filter["labels"] == %{
               "some" => %{
                 "or" => [
                   %{"name" => %{"eqIgnoreCase" => "Bug"}},
                   %{"name" => %{"eqIgnoreCase" => "Feature"}}
                 ]
               }
             }
    end

    test "--labels with an unknown label name returns empty result, not a crash" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, issues_response([]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--labels", "no-such-label"])
        end)

      assert output == "" or is_binary(output)
    end

    test "--labels composes with --team" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        if String.contains?(decoded["query"] || "", "teams(") do
          Req.Test.json(conn, %{
            "data" => %{
              "teams" => %{
                "edges" => [
                  %{
                    "node" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                    "cursor" => "c1"
                  }
                ],
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => "c1"}
              }
            }
          })
        else
          send(test_pid, {:filter, decoded["variables"]["filter"]})
          Req.Test.json(conn, issues_response([issue_map()]))
        end
      end)

      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["issue", "list", "--team", "ENG", "--labels", "Bug"])
      end)

      assert_received {:filter, filter}
      assert Map.has_key?(filter, "team")
      assert filter["labels"] == %{"some" => %{"name" => %{"eqIgnoreCase" => "Bug"}}}
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

    test "-l shows label names in compact output" do
      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "-l", "Bug"])
        end)

      assert output =~ "CRY-1"
      assert output =~ "[Bug]"
    end

    test "--labels shows label names in compact output" do
      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--labels", "Bug"])
        end)

      assert output =~ "CRY-1"
      assert output =~ "[Bug]"
    end

    test "--labels with multiple labels shows all label names in compact output" do
      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false},
              %{"id" => "l2", "name" => "Feature", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--labels", "Bug,Feature"])
        end)

      assert output =~ "CRY-1"
      assert output =~ "[Bug, Feature]"
    end

    test "compact listing without --labels does not show label brackets" do
      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output = capture_io(fn -> assert :ok = LinearCli.CLI.main(["issue", "list"]) end)

      assert output =~ "CRY-1"
      refute output =~ "[Bug]"
    end

    test "--include-labels requests label fields and shows them in compact output" do
      test_pid = self()

      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        send(test_pid, {:query, query})
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "--include-labels"])
        end)

      assert_received {:query, query}
      assert String.contains?(query, "labels")
      assert output =~ "CRY-1"
      assert output =~ "[Bug]"
    end

    test "-i short flag requests label fields and shows them in compact output" do
      test_pid = self()

      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        send(test_pid, {:query, query})
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "-i"])
        end)

      assert_received {:query, query}
      assert String.contains?(query, "labels")
      assert output =~ "CRY-1"
      assert output =~ "[Bug]"
    end

    test "-N --include-labels --all sends no assignee/date filter, no label filter, requests label fields" do
      test_pid = self()

      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Feature", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        send(test_pid, {:query, decoded["query"]})
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "list",
                     "-N",
                     "--include-labels",
                     "--all"
                   ])
        end)

      assert_received {:filter, filter}
      assert_received {:query, query}
      refute Map.has_key?(filter, "assignee")
      refute Map.has_key?(filter, "completedAt")
      refute Map.has_key?(filter, "canceledAt")
      refute Map.has_key?(filter, "labels")
      assert String.contains?(query, "labels")
      assert output =~ "CRY-1"
      assert output =~ "[Feature]"
    end

    test "-N -i --all is the same as -N --include-labels --all" do
      test_pid = self()

      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Feature", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "list", "-N", "-i", "--all"])
        end)

      assert_received {:filter, filter}
      refute Map.has_key?(filter, "assignee")
      refute Map.has_key?(filter, "labels")
      assert output =~ "[Feature]"
    end

    test "--labels --all exits 1 (Optimus parse error, no API request)" do
      Req.Test.stub(LinearCli.Api, fn _conn -> raise "no GraphQL call should happen" end)

      output =
        capture_io(fn ->
          assert catch_throw(
                   LinearCli.CLI.main(
                     ["issue", "list", "--labels", "--all"],
                     fn code -> throw({:halted, code}) end
                   )
                 ) == {:halted, 1}
        end)

      assert output =~ "--labels"
    end

    test "-s/--status composes with --include-labels" do
      test_pid = self()

      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:filter, decoded["variables"]["filter"]})
        send(test_pid, {:query, decoded["query"]})
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "list",
                     "--status",
                     "Human Review",
                     "--include-labels"
                   ])
        end)

      assert_received {:filter, filter}
      assert_received {:query, query}
      assert filter["state"] == %{"name" => %{"eqIgnoreCase" => "Human Review"}}
      assert String.contains?(query, "labels")
      assert output =~ "CRY-1"
      assert output =~ "[Bug]"
    end

    test "positional issue identifier with --include-labels uses full lookup and renders labels" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        send(test_pid, {:query, query})

        Req.Test.json(conn, %{
          "data" => %{
            "issue" =>
              issue_map(%{
                "labels" => %{
                  "nodes" => [
                    %{
                      "id" => "l1",
                      "name" => "Bug",
                      "description" => nil,
                      "isGroup" => false
                    }
                  ]
                },
                "comments" => %{"nodes" => []},
                "relations" => %{
                  "edges" => [],
                  "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                },
                "inverseRelations" => %{
                  "edges" => [],
                  "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                }
              })
          }
        })
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main(["issue", "list", "CRY-1", "--include-labels"])
        end)

      assert_received {:query, query}
      assert String.contains?(query, "issue(id: $id)")
      assert output =~ "CRY-1"
      assert output =~ "Bug"
    end

    test "--output json --include-labels contains fetched label objects in stdout" do
      test_pid = self()

      labeled_issue =
        issue_map(%{
          "labels" => %{
            "nodes" => [
              %{"id" => "l1", "name" => "Bug", "description" => nil, "isGroup" => false}
            ]
          }
        })

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query} = Jason.decode!(body)
        send(test_pid, {:query, query})
        Req.Test.json(conn, issues_response([labeled_issue]))
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "list",
                     "--output",
                     "json",
                     "--include-labels"
                   ])
        end)

      assert_received {:query, query}
      assert String.contains?(query, "labels")
      assert {:ok, [decoded]} = Jason.decode(output)
      assert [label] = decoded["labels"]
      assert label["name"] == "Bug"
    end
  end

  describe "issue view" do
    test "prints full issue details (header, description, state)" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "issue" =>
              issue_map(%{
                "state" => %{"id" => "s1", "name" => "In Progress", "type" => "started"}
              })
          }
        })
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "view", "CRY-1"])
        end)

      assert output =~ "CRY-1"
      assert output =~ "Fix the thing"
      assert output =~ "[In Progress]"
    end

    test "outputs JSON when --output json is given" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)
        Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "view", "CRY-1", "--output", "json"])
        end)

      decoded = Jason.decode!(output)
      assert decoded["identifier"] == "CRY-1"
      assert decoded["title"] == "Fix the thing"
    end

    test "lc i v ISSUE_ID alias routes to issue view" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)
        Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["i", "v", "CRY-1"])
        end)

      assert output =~ "CRY-1"
      assert output =~ "Fix the thing"
    end

    test "--web opens the issue URL in the browser and prints nothing" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "issue" => issue_map(%{"url" => "https://linear.app/the-rubyists/issue/CRY-1"})
          }
        })
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   Read.issue_view(
                     %{
                       args: %{issue_id: "CRY-1"},
                       flags: %{web: true},
                       options: %{output: "text"}
                     },
                     opener: fn url ->
                       send(test_pid, {:opened, url})
                       :ok
                     end
                   )
        end)

      assert_received {:opened, "https://linear.app/the-rubyists/issue/CRY-1"}
      assert output == ""
    end

    test "-w short flag opens the browser via the full CLI dispatch path" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "issue" => issue_map(%{"url" => "https://linear.app/the-rubyists/issue/CRY-1"})
          }
        })
      end)

      capture_io(fn ->
        assert :ok =
                 Read.issue_view(
                   %{
                     args: %{issue_id: "CRY-1"},
                     flags: %{web: true},
                     options: %{output: "text"}
                   },
                   opener: fn url ->
                     send(test_pid, {:opened, url})
                     :ok
                   end
                 )
      end)

      assert_received {:opened, "https://linear.app/the-rubyists/issue/CRY-1"}
    end

    test "--web with --output json opens browser and prints nothing" do
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => _} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "issue" => issue_map(%{"url" => "https://linear.app/the-rubyists/issue/CRY-1"})
          }
        })
      end)

      output =
        capture_io(fn ->
          assert :ok =
                   Read.issue_view(
                     %{
                       args: %{issue_id: "CRY-1"},
                       flags: %{web: true},
                       options: %{output: "json"}
                     },
                     opener: fn url ->
                       send(test_pid, {:opened, url})
                       :ok
                     end
                   )
        end)

      assert_received {:opened, "https://linear.app/the-rubyists/issue/CRY-1"}
      assert output == ""
    end
  end
end
