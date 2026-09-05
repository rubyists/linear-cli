defmodule LinearCli.Linear.IssueRelationTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear
  alias LinearCli.Linear.IssueRelation

  defp relation_node(id, type, src_id, src_ident, rel_id, rel_ident) do
    %{
      "id" => id,
      "type" => type,
      "issue" => %{
        "id" => src_id,
        "identifier" => src_ident,
        "title" => "#{src_ident} title",
        "url" => "https://example.com/#{src_ident}"
      },
      "relatedIssue" => %{
        "id" => rel_id,
        "identifier" => rel_ident,
        "title" => "#{rel_ident} title",
        "url" => "https://example.com/#{rel_ident}"
      }
    }
  end

  defp edge(node), do: %{"node" => node, "cursor" => "cursor-#{node["id"]}"}

  defp connection(edges, has_next \\ false, end_cursor \\ nil) do
    %{
      "edges" => edges,
      "pageInfo" => %{"hasNextPage" => has_next, "endCursor" => end_cursor}
    }
  end

  defp issue_response(relations_edges, inverse_edges) do
    %{
      "data" => %{
        "issue" => %{
          "relations" => connection(relations_edges),
          "inverseRelations" => connection(inverse_edges)
        }
      }
    }
  end

  test "issue_relations/1 fetches outbound relations and tags them :outbound" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      edges =
        if String.contains?(body, "inverseRelations"),
          do: [],
          else: [edge(relation_node("rel-1", "blocks", "i1", "EXT-1", "i2", "EXT-2"))]

      Req.Test.json(conn, issue_response(edges, []))
    end)

    assert {:ok, relations} = Linear.issue_relations("i1")
    outbound = Enum.filter(relations, &(&1.direction == :outbound))
    assert length(outbound) == 1
    [rel] = outbound
    assert rel.id == "rel-1"
    assert rel.type == "blocks"
    assert rel.direction == :outbound
  end

  test "issue_relations/1 returns both outbound and inbound relations" do
    call_count = :counters.new(1, [])

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      :counters.add(call_count, 1, 1)

      is_inverse = String.contains?(body, "inverseRelations")

      relations_edges =
        if is_inverse,
          do: [],
          else: [edge(relation_node("rel-1", "blocks", "i1", "EXT-1", "i2", "EXT-2"))]

      inverse_edges =
        if is_inverse,
          do: [edge(relation_node("rel-2", "blocks", "i3", "EXT-3", "i1", "EXT-1"))],
          else: []

      Req.Test.json(conn, issue_response(relations_edges, inverse_edges))
    end)

    assert {:ok, relations} = Linear.issue_relations("i1")
    assert :counters.get(call_count, 1) == 2

    outbound = Enum.filter(relations, &(&1.direction == :outbound))
    inbound = Enum.filter(relations, &(&1.direction == :inbound))

    assert length(outbound) == 1
    assert length(inbound) == 1

    [out] = outbound
    assert out.id == "rel-1"
    assert out.type == "blocks"
    assert out.issue.identifier == "EXT-1"
    assert out.related_issue.identifier == "EXT-2"

    [inv] = inbound
    assert inv.id == "rel-2"
    assert inv.type == "blocks"
    assert inv.direction == :inbound
    assert inv.issue.identifier == "EXT-3"
    assert inv.related_issue.identifier == "EXT-1"
  end

  test "issue_relations/1 returns empty list when issue has no relations" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, issue_response([], []))
    end)

    assert {:ok, []} = Linear.issue_relations("i1")
  end

  test "issue_relations/1 returns error when issue is not found" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"issue" => nil}})
    end)

    assert {:error, _} = Linear.issue_relations("nonexistent")
  end

  test "issue_relations/1 propagates API errors" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"errors" => [%{"message" => "Unauthorized"}]})
    end)

    assert {:error, _} = Linear.issue_relations("i1")
  end

  test "issue_relations/1 paginates outbound relations across pages" do
    call_count = :counters.new(1, [])

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      :counters.add(call_count, 1, 1)

      is_inverse = String.contains?(body, "inverseRelations")
      %{"variables" => vars} = Jason.decode!(body)
      after_cursor = vars["after"]

      if is_inverse do
        Req.Test.json(conn, %{
          "data" => %{
            "issue" => %{
              "inverseRelations" => connection([])
            }
          }
        })
      else
        {edges, has_next, cursor} =
          if is_nil(after_cursor) do
            {[edge(relation_node("rel-1", "related", "i1", "EXT-1", "i2", "EXT-2"))], true,
             "cursor-1"}
          else
            {[edge(relation_node("rel-2", "related", "i1", "EXT-1", "i3", "EXT-3"))], false, nil}
          end

        Req.Test.json(conn, %{
          "data" => %{
            "issue" => %{
              "relations" => connection(edges, has_next, cursor)
            }
          }
        })
      end
    end)

    assert {:ok, relations} = Linear.issue_relations("i1")
    outbound = Enum.filter(relations, &(&1.direction == :outbound))
    assert length(outbound) == 2
    assert Enum.map(outbound, & &1.id) == ["rel-1", "rel-2"]
  end

  test "IssueRelation.from_map/2 decodes outbound relation correctly" do
    map = relation_node("r1", "duplicate", "i1", "EXT-1", "i2", "EXT-2")
    rel = IssueRelation.from_map(map, :outbound)

    assert rel.id == "r1"
    assert rel.type == "duplicate"
    assert rel.direction == :outbound
    assert rel.issue.identifier == "EXT-1"
    assert rel.related_issue.identifier == "EXT-2"
  end

  test "IssueRelation.from_map/2 decodes inbound relation correctly" do
    map = relation_node("r2", "blocks", "i3", "EXT-3", "i1", "EXT-1")
    rel = IssueRelation.from_map(map, :inbound)

    assert rel.id == "r2"
    assert rel.type == "blocks"
    assert rel.direction == :inbound
    assert rel.issue.identifier == "EXT-3"
    assert rel.related_issue.identifier == "EXT-1"
  end
end
