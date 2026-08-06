defmodule LinearCli.Linear.LabelTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "labels_by_names/1 finds labels matching the given names" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => %{"names" => names}} = Jason.decode!(body)
      assert names == ["bug", "urgent"]

      Req.Test.json(conn, %{
        "data" => %{
          "issueLabels" => %{
            "edges" => [
              %{
                "node" => %{
                  "id" => "l1",
                  "name" => "bug",
                  "description" => nil,
                  "isGroup" => false
                }
              },
              %{
                "node" => %{
                  "id" => "l2",
                  "name" => "urgent",
                  "description" => nil,
                  "isGroup" => false
                }
              }
            ]
          }
        }
      })
    end)

    assert {:ok, [%Linear.Label{name: "bug"}, %Linear.Label{name: "urgent"}]} =
             Linear.labels_by_names(["bug", "urgent"])
  end

  test "labels_by_team/1 excludes group labels and labels that belong to a group (Ruby: Team#labels)" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => %{"teamId" => team_id}} = Jason.decode!(body)
      assert team_id == "t1"

      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "labels" => %{
              "nodes" => [
                %{
                  "id" => "l1",
                  "name" => "bug",
                  "description" => nil,
                  "isGroup" => false,
                  "parent" => nil
                },
                %{
                  "id" => "l2",
                  "name" => "Priority",
                  "description" => nil,
                  "isGroup" => true,
                  "parent" => nil
                },
                %{
                  "id" => "l3",
                  "name" => "High",
                  "description" => nil,
                  "isGroup" => false,
                  "parent" => %{"id" => "l2"}
                }
              ]
            }
          }
        }
      })
    end)

    assert {:ok, [%Linear.Label{id: "l1", name: "bug"}]} = Linear.labels_by_team("t1")
  end
end
