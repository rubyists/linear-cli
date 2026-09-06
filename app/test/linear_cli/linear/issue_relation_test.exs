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

  describe "create_issue_relation/3" do
    defp create_relation_payload(id, type, src_ident, rel_ident) do
      %{
        "data" => %{
          "issueRelationCreate" => %{
            "success" => true,
            "issueRelation" => relation_node(id, type, "i-src", src_ident, "i-rel", rel_ident)
          }
        }
      }
    end

    test "creates a relation and returns it tagged :outbound" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_relation_payload("rel-new", "blocks", "EXT-1", "EXT-2"))
      end)

      assert {:ok, relation} = Linear.create_issue_relation("EXT-1", "EXT-2", "blocks")
      assert relation.id == "rel-new"
      assert relation.type == "blocks"
      assert relation.direction == :outbound
      assert relation.issue.identifier == "EXT-1"
      assert relation.related_issue.identifier == "EXT-2"
    end

    test "creates a related relation" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_relation_payload("rel-r", "related", "EXT-1", "EXT-3"))
      end)

      assert {:ok, relation} = Linear.create_issue_relation("EXT-1", "EXT-3", "related")
      assert relation.type == "related"
      assert relation.direction == :outbound
    end

    test "returns error when API returns a graphql error" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "errors" => [%{"message" => "Unauthorized"}]
        })
      end)

      assert {:error, _} = Linear.create_issue_relation("EXT-1", "EXT-2", "blocks")
    end

    test "returns error tagged :duplicate_relation when relation already exists" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "errors" => [
            %{"message" => "A relation of this type already exists between these issues"}
          ]
        })
      end)

      assert {:error, %Ash.Error.Unknown{errors: [%{value: [{:duplicate_relation, _msg}]} | _]}} =
               Linear.create_issue_relation("EXT-1", "EXT-2", "blocks")
    end

    test "sends issueId, relatedIssueId, and type to the API" do
      parent = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => vars} = Jason.decode!(body)
        send(parent, {:vars, vars})
        Req.Test.json(conn, create_relation_payload("r1", "blocks", "EXT-1", "EXT-2"))
      end)

      Linear.create_issue_relation("EXT-1", "EXT-2", "blocks")

      assert_received {:vars,
                       %{"issueId" => "EXT-1", "relatedIssueId" => "EXT-2", "type" => "blocks"}}
    end
  end

  describe "delete_issue_relation/1" do
    defp delete_success_response(entity_id) do
      %{
        "data" => %{
          "issueRelationDelete" => %{
            "success" => true,
            "entityId" => entity_id
          }
        }
      }
    end

    defp make_relation(id) do
      IssueRelation.from_map(
        %{
          "id" => id,
          "type" => "blocks",
          "issue" => %{"id" => "i1", "identifier" => "EXT-1", "title" => "t", "url" => "u"},
          "relatedIssue" => %{"id" => "i2", "identifier" => "EXT-2", "title" => "t", "url" => "u"}
        },
        :outbound
      )
    end

    test "deletes a relation and returns :ok" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, delete_success_response("rel-1"))
      end)

      assert :ok = Linear.delete_issue_relation(make_relation("rel-1"))
    end

    test "sends the relation id to the API" do
      parent = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => vars} = Jason.decode!(body)
        send(parent, {:vars, vars})
        Req.Test.json(conn, delete_success_response("rel-xyz"))
      end)

      Linear.delete_issue_relation(make_relation("rel-xyz"))

      assert_received {:vars, %{"id" => "rel-xyz"}}
    end

    test "returns error when API returns a graphql error" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "Unauthorized"}]})
      end)

      assert {:error, _} = Linear.delete_issue_relation(make_relation("rel-1"))
    end

    test "returns error on unexpected response shape" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{"issueRelationDelete" => %{"success" => false, "entityId" => nil}}
        })
      end)

      assert {:error, _} = Linear.delete_issue_relation(make_relation("rel-1"))
    end
  end
end
