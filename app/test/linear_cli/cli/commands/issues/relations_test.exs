defmodule LinearCli.CLI.Commands.Issues.RelationsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Commands.Issues.Relations

  describe "issue relation list" do
    defp relation_node(id, type, src_ident, rel_ident) do
      %{
        "id" => id,
        "type" => type,
        "issue" => %{
          "id" => "i-src",
          "identifier" => src_ident,
          "title" => "#{src_ident} title",
          "url" => "u"
        },
        "relatedIssue" => %{
          "id" => "i-rel",
          "identifier" => rel_ident,
          "title" => "#{rel_ident} title",
          "url" => "u"
        }
      }
    end

    defp relation_edge(node), do: %{"node" => node, "cursor" => "c-#{node["id"]}"}

    defp relations_stub(out_edges, inv_edges) do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        is_inverse = String.contains?(body, "inverseRelations")

        data =
          if is_inverse do
            %{
              "data" => %{
                "issue" => %{
                  "inverseRelations" => %{
                    "edges" => inv_edges,
                    "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                  }
                }
              }
            }
          else
            %{
              "data" => %{
                "issue" => %{
                  "relations" => %{
                    "edges" => out_edges,
                    "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                  }
                }
              }
            }
          end

        Req.Test.json(conn, data)
      end)
    end

    test "displays Blocks section for outbound blocks relations" do
      relations_stub(
        [relation_edge(relation_node("r1", "blocks", "EXT-1", "EXT-2"))],
        []
      )

      output =
        capture_io(fn ->
          Relations.issue_relation_list(%{args: %{issue_id: "EXT-1"}, options: %{output: "text"}})
        end)

      assert output =~ "Blocks:"
      assert output =~ "EXT-2"
    end

    test "displays Blocked by section for inbound blocks relations" do
      relations_stub(
        [],
        [relation_edge(relation_node("r1", "blocks", "EXT-3", "EXT-1"))]
      )

      output =
        capture_io(fn ->
          Relations.issue_relation_list(%{args: %{issue_id: "EXT-1"}, options: %{output: "text"}})
        end)

      assert output =~ "Blocked by:"
      assert output =~ "EXT-3"
    end

    test "returns empty output when issue has no relations" do
      relations_stub([], [])

      output =
        capture_io(fn ->
          Relations.issue_relation_list(%{args: %{issue_id: "EXT-1"}, options: %{output: "text"}})
        end)

      assert String.trim(output) == ""
    end

    test "JSON output includes all relation fields" do
      relations_stub(
        [relation_edge(relation_node("r1", "blocks", "EXT-1", "EXT-2"))],
        []
      )

      output =
        capture_io(fn ->
          Relations.issue_relation_list(%{args: %{issue_id: "EXT-1"}, options: %{output: "json"}})
        end)

      [entry] = Jason.decode!(output)
      assert entry["id"] == "r1"
      assert entry["type"] == "blocks"
      assert entry["direction"] == "outbound"
    end
  end

  describe "issue relation add" do
    defp create_success_response(id, type, src_ident, rel_ident) do
      %{
        "data" => %{
          "issueRelationCreate" => %{
            "success" => true,
            "issueRelation" => %{
              "id" => id,
              "type" => type,
              "issue" => %{
                "id" => "i-src",
                "identifier" => src_ident,
                "title" => "#{src_ident} title",
                "url" => "https://example.com/#{src_ident}"
              },
              "relatedIssue" => %{
                "id" => "i-rel",
                "identifier" => rel_ident,
                "title" => "#{rel_ident} title",
                "url" => "https://example.com/#{rel_ident}"
              }
            }
          }
        }
      }
    end

    defp create_duplicate_response do
      %{
        "errors" => [
          %{"message" => "A relation of this type already exists between these issues"}
        ]
      }
    end

    defp create_error_response(message) do
      %{"errors" => [%{"message" => message}]}
    end

    defp add_parse_result(subject, related_ids, type) do
      %{
        unknown: [subject | related_ids],
        options: %{output: "text", type: type}
      }
    end

    test "creates a blocks relation and prints the result" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_success_response("r1", "blocks", "EXT-1", "EXT-2"))
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-2"], "blocks"))
        end)

      assert output =~ "EXT-1 now blocks EXT-2"
    end

    test "blocked-by sends reversed endpoints to Linear" do
      parent = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => vars} = Jason.decode!(body)
        send(parent, {:vars, vars})
        Req.Test.json(conn, create_success_response("r1", "blocks", "EXT-3", "EXT-1"))
      end)

      capture_io(fn ->
        Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-3"], "blocked-by"))
      end)

      assert_received {:vars,
                       %{"issueId" => "EXT-3", "relatedIssueId" => "EXT-1", "type" => "blocks"}}
    end

    test "blocked-by prints direction from subject's perspective" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_success_response("r1", "blocks", "EXT-3", "EXT-1"))
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-3"], "blocked-by"))
        end)

      assert output =~ "EXT-3 now blocks EXT-1"
    end

    test "processes multiple related issues" do
      call_count = :counters.new(1, [])

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        :counters.add(call_count, 1, 1)
        %{"variables" => %{"relatedIssueId" => related}} = Jason.decode!(body)
        Req.Test.json(conn, create_success_response("r#{related}", "blocks", "EXT-1", related))
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-2", "EXT-3"], "blocks"))
        end)

      assert :counters.get(call_count, 1) == 2
      assert output =~ "EXT-1 now blocks EXT-2"
      assert output =~ "EXT-1 now blocks EXT-3"
    end

    test "treats duplicate relation as informative no-op" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_duplicate_response())
      end)

      output =
        capture_io(fn ->
          result = Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-2"], "blocks"))
          assert result == :ok
        end)

      assert output =~ "already exists"
    end

    test "rejects self-link without calling the API" do
      Req.Test.stub(LinearCli.Api, fn _conn ->
        raise "should not be called"
      end)

      output_stderr =
        capture_io(:stderr, fn ->
          result = Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-1"], "blocks"))
          assert {:error, {:smells_bad, _}} = result
        end)

      assert output_stderr =~ "self-link"
    end

    test "returns error when no related issues provided" do
      assert {:error, {:smells_bad, _}} =
               Relations.issue_relation_add(%{
                 unknown: ["EXT-1"],
                 options: %{output: "text", type: "blocks"}
               })
    end

    test "returns error when no issue ids provided" do
      assert {:error, {:smells_bad, _}} =
               Relations.issue_relation_add(%{
                 unknown: [],
                 options: %{output: "text", type: "blocks"}
               })
    end

    test "exits non-zero on full failure and prints to stderr" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_error_response("Unauthorized"))
      end)

      stderr =
        capture_io(:stderr, fn ->
          result = Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-2"], "blocks"))
          assert {:error, {:smells_bad, msg}} = result
          assert msg =~ "failed"
        end)

      assert stderr =~ "EXT-2: Linear API error: Unauthorized"
    end

    test "partial failure: succeeds for valid targets, errors for failed targets" do
      call_count = :counters.new(1, [])

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        :counters.add(call_count, 1, 1)
        %{"variables" => %{"relatedIssueId" => related}} = Jason.decode!(body)

        if related == "EXT-2" do
          Req.Test.json(conn, create_success_response("r1", "blocks", "EXT-1", "EXT-2"))
        else
          Req.Test.json(conn, create_error_response("Unauthorized"))
        end
      end)

      stderr =
        capture_io(:stderr, fn ->
          output =
            capture_io(fn ->
              result =
                Relations.issue_relation_add(
                  add_parse_result("EXT-1", ["EXT-2", "EXT-bad"], "blocks")
                )

              assert {:error, {:smells_bad, _}} = result
            end)

          send(self(), {:relation_add_output, output})
        end)

      assert_received {:relation_add_output, output}
      assert output =~ "EXT-1 now blocks EXT-2"
      assert stderr =~ "EXT-bad: Linear API error: Unauthorized"
      assert :counters.get(call_count, 1) == 2
    end

    test "JSON output contains per-target status and relation for success" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_success_response("r1", "blocks", "EXT-1", "EXT-2"))
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(%{
            unknown: ["EXT-1", "EXT-2"],
            options: %{output: "json", type: "blocks"}
          })
        end)

      [entry] = Jason.decode!(output)
      assert entry["status"] == "created"
      assert entry["target"] == "EXT-2"
      assert entry["relation"]["type"] == "blocks"
    end

    test "JSON output shows exists status for duplicate" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_duplicate_response())
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(%{
            unknown: ["EXT-1", "EXT-2"],
            options: %{output: "json", type: "blocks"}
          })
        end)

      [entry] = Jason.decode!(output)
      assert entry["status"] == "exists"
      assert entry["target"] == "EXT-2"
    end

    test "JSON output shows error status for self-link" do
      Req.Test.stub(LinearCli.Api, fn _conn -> raise "should not be called" end)

      output =
        capture_io(:stderr, fn ->
          output_stdout =
            capture_io(fn ->
              Relations.issue_relation_add(%{
                unknown: ["EXT-1", "EXT-1"],
                options: %{output: "json", type: "blocks"}
              })
            end)

          [entry] = Jason.decode!(output_stdout)
          assert entry["status"] == "error"
          assert entry["target"] == "EXT-1"
          assert entry["message"] =~ "self-link"
        end)

      assert output == ""
    end

    test "JSON output shows actual error message for API failures" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_error_response("Unauthorized"))
      end)

      {_result, output} =
        with_io(fn ->
          Relations.issue_relation_add(%{
            unknown: ["EXT-1", "EXT-2"],
            options: %{output: "json", type: "blocks"}
          })
        end)

      [entry] = Jason.decode!(output)
      assert entry["status"] == "error"
      assert entry["target"] == "EXT-2"
      assert entry["message"] =~ "Unauthorized"
    end

    test "creates a related relation and prints grammatically correct text" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_success_response("r1", "related", "EXT-1", "EXT-2"))
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-2"], "related"))
        end)

      assert output =~ "EXT-1 is now related to EXT-2"
    end

    test "creates a duplicate relation and prints grammatically correct text" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, create_success_response("r1", "duplicate", "EXT-1", "EXT-2"))
      end)

      output =
        capture_io(fn ->
          Relations.issue_relation_add(add_parse_result("EXT-1", ["EXT-2"], "duplicate"))
        end)

      assert output =~ "EXT-1 is now a duplicate of EXT-2"
    end
  end

  describe "issue relation remove" do
    defp remove_parse_result(subject, related_ids, type) do
      %{
        unknown: [subject | related_ids],
        options: %{output: "text", type: type}
      }
    end

    defp remove_relations_stub(out_nodes, inv_nodes) do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        cond do
          String.contains?(body, "issueRelationDelete") ->
            %{"variables" => %{"id" => id}} = decoded

            Req.Test.json(conn, %{
              "data" => %{
                "issueRelationDelete" => %{"success" => true, "entityId" => id}
              }
            })

          String.contains?(body, "inverseRelations") ->
            Req.Test.json(conn, %{
              "data" => %{
                "issue" => %{
                  "inverseRelations" => %{
                    "edges" => Enum.map(inv_nodes, &%{"node" => &1, "cursor" => "c"}),
                    "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                  }
                }
              }
            })

          true ->
            Req.Test.json(conn, %{
              "data" => %{
                "issue" => %{
                  "relations" => %{
                    "edges" => Enum.map(out_nodes, &%{"node" => &1, "cursor" => "c"}),
                    "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                  }
                }
              }
            })
        end
      end)
    end

    defp remove_relation_node(id, type, src_ident, rel_ident) do
      %{
        "id" => id,
        "type" => type,
        "issue" => %{
          "id" => "i-src",
          "identifier" => src_ident,
          "title" => "#{src_ident} title",
          "url" => "https://example.com/#{src_ident}"
        },
        "relatedIssue" => %{
          "id" => "i-rel",
          "identifier" => rel_ident,
          "title" => "#{rel_ident} title",
          "url" => "https://example.com/#{rel_ident}"
        }
      }
    end

    test "removes a blocks relation and prints the result" do
      remove_relations_stub(
        [remove_relation_node("r1", "blocks", "EXT-1", "EXT-2")],
        []
      )

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-2"], "blocks")
                   )
        end)

      assert output =~ "EXT-1 no longer blocks EXT-2"
    end

    test "removes a related relation and prints correct text" do
      remove_relations_stub(
        [remove_relation_node("r1", "related", "EXT-1", "EXT-2")],
        []
      )

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-2"], "related")
                   )
        end)

      assert output =~ "EXT-1 is no longer related to EXT-2"
    end

    test "removes a duplicate relation and prints correct text" do
      remove_relations_stub(
        [remove_relation_node("r1", "duplicate", "EXT-1", "EXT-2")],
        []
      )

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-2"], "duplicate")
                   )
        end)

      assert output =~ "EXT-1 is no longer a duplicate of EXT-2"
    end

    test "absent relation is a no-op and returns :ok" do
      remove_relations_stub([], [])

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-2"], "blocks")
                   )
        end)

      assert output =~ "not found"
    end

    test "blocked-by matches the inbound blocks relation" do
      remove_relations_stub(
        [],
        [remove_relation_node("r1", "blocks", "EXT-3", "EXT-1")]
      )

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-3"], "blocked-by")
                   )
        end)

      assert output =~ "EXT-3 no longer blocks EXT-1"
    end

    test "blocked-by with no matching inbound relation is a no-op" do
      remove_relations_stub([], [])

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-3"], "blocked-by")
                   )
        end)

      assert output =~ "not found"
    end

    test "processes multiple related issues independently" do
      remove_relations_stub(
        [
          remove_relation_node("r1", "blocks", "EXT-1", "EXT-2"),
          remove_relation_node("r2", "blocks", "EXT-1", "EXT-3")
        ],
        []
      )

      output =
        capture_io(fn ->
          assert :ok =
                   Relations.issue_relation_remove(
                     remove_parse_result("EXT-1", ["EXT-2", "EXT-3"], "blocks")
                   )
        end)

      assert output =~ "EXT-1 no longer blocks EXT-2"
      assert output =~ "EXT-1 no longer blocks EXT-3"
    end

    test "rejects self-link without calling the delete mutation" do
      remove_relations_stub([], [])

      output_stderr =
        capture_io(:stderr, fn ->
          result =
            Relations.issue_relation_remove(remove_parse_result("EXT-1", ["EXT-1"], "blocks"))

          assert {:error, {:smells_bad, _}} = result
        end)

      assert output_stderr =~ "self-link"
    end

    test "returns error when no related issues provided" do
      assert {:error, {:smells_bad, _}} =
               Relations.issue_relation_remove(%{
                 unknown: ["EXT-1"],
                 options: %{output: "text", type: "blocks"}
               })
    end

    test "returns error when no issue ids provided" do
      assert {:error, {:smells_bad, _}} =
               Relations.issue_relation_remove(%{
                 unknown: [],
                 options: %{output: "text", type: "blocks"}
               })
    end

    test "ambiguous match fails that target and lists all matching ids" do
      remove_relations_stub(
        [
          remove_relation_node("r1", "blocks", "EXT-1", "EXT-2"),
          remove_relation_node("r2", "blocks", "EXT-1", "EXT-2")
        ],
        []
      )

      output_stderr =
        capture_io(:stderr, fn ->
          result =
            capture_io(fn ->
              Relations.issue_relation_remove(remove_parse_result("EXT-1", ["EXT-2"], "blocks"))
            end)

          _ = result
        end)

      assert output_stderr =~ "ambiguous"
      assert output_stderr =~ "r1"
      assert output_stderr =~ "r2"
    end

    test "ambiguous match exits non-zero" do
      remove_relations_stub(
        [
          remove_relation_node("r1", "blocks", "EXT-1", "EXT-2"),
          remove_relation_node("r2", "blocks", "EXT-1", "EXT-2")
        ],
        []
      )

      {result, _output} =
        with_io(fn ->
          Relations.issue_relation_remove(remove_parse_result("EXT-1", ["EXT-2"], "blocks"))
        end)

      assert {:error, {:smells_bad, msg}} = result
      assert msg =~ "failed"
    end

    test "partial failure: succeeds for absent target, errors for ambiguous" do
      remove_relations_stub(
        [
          remove_relation_node("r1", "blocks", "EXT-1", "EXT-2"),
          remove_relation_node("r2", "blocks", "EXT-1", "EXT-2")
        ],
        []
      )

      {result, _output} =
        with_io(fn ->
          Relations.issue_relation_remove(
            remove_parse_result("EXT-1", ["EXT-2", "EXT-3"], "blocks")
          )
        end)

      assert {:error, {:smells_bad, _}} = result
    end

    test "API error on delete causes that target to fail" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        if String.contains?(body, "issueRelationDelete") do
          Req.Test.json(conn, %{"errors" => [%{"message" => "Unauthorized"}]})
        else
          data =
            if String.contains?(body, "inverseRelations") do
              %{
                "data" => %{
                  "issue" => %{
                    "inverseRelations" => %{
                      "edges" => [],
                      "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                    }
                  }
                }
              }
            else
              %{
                "data" => %{
                  "issue" => %{
                    "relations" => %{
                      "edges" => [
                        %{
                          "node" => remove_relation_node("r1", "blocks", "EXT-1", "EXT-2"),
                          "cursor" => "c"
                        }
                      ],
                      "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                    }
                  }
                }
              }
            end

          Req.Test.json(conn, data)
        end
      end)

      {result, _output} =
        with_io(fn ->
          Relations.issue_relation_remove(remove_parse_result("EXT-1", ["EXT-2"], "blocks"))
        end)

      assert {:error, {:smells_bad, _}} = result
    end

    test "JSON output shows removed status with relation for success" do
      remove_relations_stub(
        [remove_relation_node("r1", "blocks", "EXT-1", "EXT-2")],
        []
      )

      output =
        capture_io(fn ->
          Relations.issue_relation_remove(%{
            unknown: ["EXT-1", "EXT-2"],
            options: %{output: "json", type: "blocks"}
          })
        end)

      [entry] = Jason.decode!(output)
      assert entry["status"] == "removed"
      assert entry["target"] == "EXT-2"
      assert entry["relation"]["type"] == "blocks"
    end

    test "JSON output shows absent status for missing relation" do
      remove_relations_stub([], [])

      output =
        capture_io(fn ->
          Relations.issue_relation_remove(%{
            unknown: ["EXT-1", "EXT-2"],
            options: %{output: "json", type: "blocks"}
          })
        end)

      [entry] = Jason.decode!(output)
      assert entry["status"] == "absent"
      assert entry["target"] == "EXT-2"
    end

    test "JSON output shows error with all ids for ambiguous match" do
      remove_relations_stub(
        [
          remove_relation_node("r1", "blocks", "EXT-1", "EXT-2"),
          remove_relation_node("r2", "blocks", "EXT-1", "EXT-2")
        ],
        []
      )

      output =
        capture_io(fn ->
          Relations.issue_relation_remove(%{
            unknown: ["EXT-1", "EXT-2"],
            options: %{output: "json", type: "blocks"}
          })
        end)

      [entry] = Jason.decode!(output)
      assert entry["status"] == "error"
      assert entry["target"] == "EXT-2"
      assert entry["message"] =~ "ambiguous"
      assert entry["message"] =~ "r1"
      assert entry["message"] =~ "r2"
    end

    test "JSON output shows error for self-link" do
      remove_relations_stub([], [])

      output =
        capture_io(:stderr, fn ->
          output_stdout =
            capture_io(fn ->
              Relations.issue_relation_remove(%{
                unknown: ["EXT-1", "EXT-1"],
                options: %{output: "json", type: "blocks"}
              })
            end)

          [entry] = Jason.decode!(output_stdout)
          assert entry["status"] == "error"
          assert entry["message"] =~ "self-link"
        end)

      assert output == ""
    end
  end
end
