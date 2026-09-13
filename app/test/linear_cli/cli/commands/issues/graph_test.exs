defmodule LinearCli.CLI.Commands.Issues.GraphTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Commands.Issues.Graph
  alias LinearCli.CLI.Display

  # --- Helpers ---

  defp rel_node(id, type, src_ident, src_state, rel_ident, rel_state) do
    %{
      "id" => id,
      "type" => type,
      "issue" => endpoint_map(src_ident, src_state),
      "relatedIssue" => endpoint_map(rel_ident, rel_state)
    }
  end

  defp endpoint_map(identifier, state_name) do
    state = if state_name, do: %{"name" => state_name}, else: nil

    %{
      "id" => "id-#{identifier}",
      "identifier" => identifier,
      "title" => "Title of #{identifier}",
      "url" => "https://example.com/#{identifier}",
      "state" => state
    }
  end

  defp rel_edge(node), do: %{"node" => node, "cursor" => "c-#{node["id"]}"}

  defp page_info(has_next \\ false),
    do: %{"hasNextPage" => has_next, "endCursor" => nil}

  defp relations_response(out_edges, inv_edges) do
    fn body ->
      is_inverse = String.contains?(body, "inverseRelations")

      if is_inverse do
        %{
          "data" => %{
            "issue" => %{
              "inverseRelations" => %{"edges" => inv_edges, "pageInfo" => page_info()}
            }
          }
        }
      else
        %{
          "data" => %{
            "issue" => %{
              "relations" => %{"edges" => out_edges, "pageInfo" => page_info()}
            }
          }
        }
      end
    end
  end

  # Stubs one or more issue-relation calls, dispatching by issueId variable.
  # `by_id` is a map of identifier -> {out_edges, inv_edges}.
  defp stub_relations(by_id) do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      issue_id = decoded["variables"]["issueId"]
      {out, inv} = Map.fetch!(by_id, issue_id)
      response_fn = relations_response(out, inv)
      Req.Test.json(conn, response_fn.(body))
    end)
  end

  defp root_issue(identifier, state_name \\ "Triage") do
    state = if state_name, do: %{name: state_name}, else: nil

    %{
      id: "id-#{identifier}",
      identifier: identifier,
      title: "Title of #{identifier}",
      state: state
    }
  end

  # --- Tests ---

  describe "Graph.build/2" do
    test "returns just the root node when issue has no blocks relations" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Req.Test.json(conn, relations_response([], []).(body))
      end)

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "Triage"))

      assert graph.root == "EXT-56"
      assert length(graph.nodes) == 1
      assert [%{identifier: "EXT-56", status: "Triage"}] = graph.nodes
      assert graph.edges == []
    end

    test "non-blocks relations are excluded" do
      related_edge = rel_edge(rel_node("r1", "related", "EXT-56", nil, "EXT-99", nil))
      duplicate_edge = rel_edge(rel_node("r2", "duplicate", "EXT-56", nil, "EXT-88", nil))

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Req.Test.json(conn, relations_response([related_edge, duplicate_edge], []).(body))
      end)

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56"))

      # Only the root - related and duplicate are ignored
      assert length(graph.nodes) == 1
      assert graph.edges == []
    end

    test "single outbound blocks edge (root blocks EXT-57)" do
      # outbound: EXT-56 -> EXT-57
      out_edge = rel_edge(rel_node("r1", "blocks", "EXT-56", "In Progress", "EXT-57", "Todo"))

      stub_relations(%{
        "EXT-56" => {[out_edge], []},
        "EXT-57" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "In Progress"))

      ids = Enum.map(graph.nodes, & &1.identifier)
      assert "EXT-56" in ids
      assert "EXT-57" in ids
      assert graph.edges == [%{source: "EXT-56", target: "EXT-57"}]
      assert Enum.find(graph.nodes, &(&1.identifier == "EXT-57")).status == "Todo"
    end

    test "single inbound blocks edge (EXT-40 blocks root)" do
      # inbound: EXT-40 -> EXT-56
      inv_edge = rel_edge(rel_node("r1", "blocks", "EXT-40", "Done", "EXT-56", "Triage"))

      stub_relations(%{
        "EXT-56" => {[], [inv_edge]},
        "EXT-40" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "Triage"))

      ids = Enum.map(graph.nodes, & &1.identifier)
      assert "EXT-40" in ids
      assert "EXT-56" in ids
      assert graph.edges == [%{source: "EXT-40", target: "EXT-56"}]
    end

    test "transitive chain: EXT-40 -> EXT-56 -> EXT-57" do
      inv_edge = rel_edge(rel_node("r1", "blocks", "EXT-40", "Done", "EXT-56", "Triage"))
      out_edge = rel_edge(rel_node("r2", "blocks", "EXT-56", "Triage", "EXT-57", "Todo"))

      stub_relations(%{
        "EXT-56" => {[out_edge], [inv_edge]},
        "EXT-40" => {[], []},
        "EXT-57" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "Triage"))

      ids = Enum.map(graph.nodes, & &1.identifier)
      assert "EXT-40" in ids
      assert "EXT-56" in ids
      assert "EXT-57" in ids

      assert %{source: "EXT-40", target: "EXT-56"} in graph.edges
      assert %{source: "EXT-56", target: "EXT-57"} in graph.edges
    end

    test "branching: root blocks two issues" do
      out_a = rel_edge(rel_node("r1", "blocks", "EXT-56", "Triage", "EXT-57", "Todo"))
      out_b = rel_edge(rel_node("r2", "blocks", "EXT-56", "Triage", "EXT-58", "Todo"))

      stub_relations(%{
        "EXT-56" => {[out_a, out_b], []},
        "EXT-57" => {[], []},
        "EXT-58" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "Triage"))

      ids = Enum.map(graph.nodes, & &1.identifier) |> Enum.sort()
      assert ids == ["EXT-56", "EXT-57", "EXT-58"]
      assert length(graph.edges) == 2
    end

    test "shared dependency (diamond): two issues block root, root blocks one" do
      inv_a = rel_edge(rel_node("r1", "blocks", "EXT-40", "Done", "EXT-56", "Triage"))
      inv_b = rel_edge(rel_node("r2", "blocks", "EXT-55", "In Progress", "EXT-56", "Triage"))
      out_c = rel_edge(rel_node("r3", "blocks", "EXT-56", "Triage", "EXT-57", "Todo"))

      stub_relations(%{
        "EXT-56" => {[out_c], [inv_a, inv_b]},
        "EXT-40" => {[], []},
        "EXT-55" => {[], []},
        "EXT-57" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "Triage"))

      ids = Enum.map(graph.nodes, & &1.identifier) |> Enum.sort()
      assert ids == ["EXT-40", "EXT-55", "EXT-56", "EXT-57"]
      assert length(graph.edges) == 3
    end

    test "cycle: A blocks B, B blocks A" do
      # EXT-56 has an outbound edge to EXT-99
      out = rel_edge(rel_node("r1", "blocks", "EXT-56", "Triage", "EXT-99", "Todo"))
      # EXT-99 has an outbound edge back to EXT-56 (cycle)
      out_back = rel_edge(rel_node("r2", "blocks", "EXT-99", "Todo", "EXT-56", "Triage"))

      stub_relations(%{
        "EXT-56" => {[out], []},
        "EXT-99" => {[out_back], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56", "Triage"))

      # Should terminate finitely with each node once
      ids = Enum.map(graph.nodes, & &1.identifier) |> Enum.sort()
      assert ids == ["EXT-56", "EXT-99"]
    end

    test "nodes are sorted by identifier" do
      out_a = rel_edge(rel_node("r1", "blocks", "EXT-56", "Triage", "EXT-99", "Todo"))
      out_b = rel_edge(rel_node("r2", "blocks", "EXT-56", "Triage", "EXT-10", "Todo"))

      stub_relations(%{
        "EXT-56" => {[out_a, out_b], []},
        "EXT-99" => {[], []},
        "EXT-10" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56"))

      ids = Enum.map(graph.nodes, & &1.identifier)
      assert ids == Enum.sort(ids)
    end

    test "edges are sorted by (source, target)" do
      out_b = rel_edge(rel_node("r1", "blocks", "EXT-56", "Triage", "EXT-99", "Todo"))
      out_a = rel_edge(rel_node("r2", "blocks", "EXT-56", "Triage", "EXT-10", "Todo"))

      stub_relations(%{
        "EXT-56" => {[out_b, out_a], []},
        "EXT-99" => {[], []},
        "EXT-10" => {[], []}
      })

      assert {:ok, graph} = Graph.build("EXT-56", root_issue("EXT-56"))

      pairs = Enum.map(graph.edges, fn e -> {e.source, e.target} end)
      assert pairs == Enum.sort(pairs)
    end

    test "error from issue_relations is returned with the failing issue identifier" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        Req.Test.json(conn, %{
          "errors" => [%{"message" => "Unauthorized"}]
        })
      end)

      assert {:error, {"EXT-56", _reason}} = Graph.build("EXT-56", root_issue("EXT-56"))
    end
  end

  describe "Display.show_graph/2 text output" do
    test "includes legend, Issues section, and Edges section" do
      graph = %{
        root: "EXT-56",
        nodes: [
          %{identifier: "EXT-40", status: "Done", title: "Predecessor"},
          %{identifier: "EXT-56", status: "Triage", title: "Root issue"}
        ],
        edges: [%{source: "EXT-40", target: "EXT-56"}]
      }

      output = capture_io(fn -> Display.show_graph(graph) end)

      assert output =~ "Dependency graph"
      assert output =~ "A -> B means A blocks B"
      assert output =~ "EXT-40"
      assert output =~ "EXT-56"
      assert output =~ "Done"
      assert output =~ "Triage"
      assert output =~ "(root)"
    end

    test "empty graph shows root with no edges" do
      graph = %{
        root: "EXT-56",
        nodes: [%{identifier: "EXT-56", status: "Triage", title: "Solo issue"}],
        edges: []
      }

      output = capture_io(fn -> Display.show_graph(graph) end)

      assert output =~ "EXT-56"
      assert output =~ "Solo issue"
      assert output =~ "(none)"
    end

    test "Issues table header is ISSUE STATUS TITLE" do
      graph = %{
        root: "EXT-1",
        nodes: [%{identifier: "EXT-1", status: "Todo", title: "T"}],
        edges: []
      }

      output = capture_io(fn -> Display.show_graph(graph) end)

      assert output =~ "ISSUE"
      assert output =~ "STATUS"
      assert output =~ "TITLE"
    end

    test "Edges table header is SOURCE TARGET" do
      graph = %{
        root: "EXT-2",
        nodes: [
          %{identifier: "EXT-1", status: "Done", title: "A"},
          %{identifier: "EXT-2", status: "Todo", title: "B"}
        ],
        edges: [%{source: "EXT-1", target: "EXT-2"}]
      }

      output = capture_io(fn -> Display.show_graph(graph) end)

      assert output =~ "SOURCE"
      assert output =~ "TARGET"
      assert output =~ "EXT-1"
      assert output =~ "EXT-2"
    end

    test "diagram direction is deterministic across runs" do
      graph = %{
        root: "EXT-56",
        nodes: [
          %{identifier: "EXT-40", status: "Done", title: "A"},
          %{identifier: "EXT-56", status: "Triage", title: "Root"},
          %{identifier: "EXT-57", status: "Todo", title: "C"}
        ],
        edges: [
          %{source: "EXT-40", target: "EXT-56"},
          %{source: "EXT-56", target: "EXT-57"}
        ]
      }

      output1 = capture_io(fn -> Display.show_graph(graph) end)
      output2 = capture_io(fn -> Display.show_graph(graph) end)

      assert output1 == output2
    end
  end

  describe "Display.show_graph/2 JSON output" do
    test "emits {root, nodes, edges} object with no extra fields" do
      graph = %{
        root: "EXT-56",
        nodes: [
          %{identifier: "EXT-40", status: "Done", title: "Add thing"},
          %{identifier: "EXT-56", status: "Triage", title: "Root"}
        ],
        edges: [%{source: "EXT-40", target: "EXT-56"}]
      }

      output = capture_io(fn -> Display.show_graph(graph, %{output: "json"}) end)

      decoded = Jason.decode!(output)
      assert Map.keys(decoded) |> Enum.sort() == ["edges", "nodes", "root"]
      assert decoded["root"] == "EXT-56"
      assert length(decoded["nodes"]) == 2
      assert length(decoded["edges"]) == 1
      [edge] = decoded["edges"]
      assert edge["source"] == "EXT-40"
      assert edge["target"] == "EXT-56"
    end

    test "JSON node has identifier, status, title keys" do
      graph = %{
        root: "EXT-56",
        nodes: [%{identifier: "EXT-56", status: "Triage", title: "Root"}],
        edges: []
      }

      output = capture_io(fn -> Display.show_graph(graph, %{output: "json"}) end)

      decoded = Jason.decode!(output)
      [node] = decoded["nodes"]
      assert Map.keys(node) |> Enum.sort() == ["identifier", "status", "title"]
    end
  end

  describe "lc issue view --graph CLI integration" do
    defp full_issue_response(identifier, state_name) do
      state = %{"id" => "s1", "name" => state_name, "type" => "triage"}
      %{"data" => %{"issue" => issue_map(%{"identifier" => identifier, "state" => state})}}
    end

    defp stub_view_and_relations(identifier, state_name, out_edges, inv_edges) do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            Req.Test.json(conn, full_issue_response(identifier, state_name))

          String.contains?(body, "inverseRelations") ->
            Req.Test.json(
              conn,
              %{
                "data" => %{
                  "issue" => %{
                    "inverseRelations" => %{"edges" => inv_edges, "pageInfo" => page_info()}
                  }
                }
              }
            )

          true ->
            Req.Test.json(
              conn,
              %{
                "data" => %{
                  "issue" => %{
                    "relations" => %{"edges" => out_edges, "pageInfo" => page_info()}
                  }
                }
              }
            )
        end
      end)
    end

    test "--graph flag is accepted and prints Dependency graph header" do
      stub_view_and_relations("EXT-56", "Triage", [], [])

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "view", "EXT-56", "--graph"])
        end)

      assert output =~ "Dependency graph"
      assert output =~ "EXT-56"
    end

    test "--graph and --web together return a usage error" do
      output =
        capture_io(:stderr, fn ->
          assert catch_throw(
                   LinearCli.CLI.main(
                     ["issue", "view", "EXT-56", "--graph", "--web"],
                     fn code -> throw({:halted, code}) end
                   )
                 ) == {:halted, 22}
        end)

      assert output =~ "--graph" or output =~ "web"
    end

    test "without --graph, issue view output is unchanged" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)
        Req.Test.json(conn, full_issue_response("EXT-56", "In Progress"))
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "view", "EXT-56"])
        end)

      assert output =~ "EXT-56"
      assert output =~ "[In Progress]"
      refute output =~ "Dependency graph"
    end

    test "--graph --output json emits graph JSON not issue JSON" do
      stub_view_and_relations("EXT-56", "Triage", [], [])

      output =
        capture_io(fn ->
          assert :ok =
                   LinearCli.CLI.main([
                     "issue",
                     "view",
                     "EXT-56",
                     "--graph",
                     "--output",
                     "json"
                   ])
        end)

      decoded = Jason.decode!(output)
      # Must be the graph shape, not the issue shape
      assert Map.has_key?(decoded, "root")
      assert Map.has_key?(decoded, "nodes")
      assert Map.has_key?(decoded, "edges")
      refute Map.has_key?(decoded, "identifier")
    end
  end
end
