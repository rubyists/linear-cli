defmodule LinearCli.RolloverTest do
  use ExUnit.Case, async: true

  alias LinearCli.Rollover

  describe "shift_month/2" do
    test "shifts back a month within the same year" do
      assert Rollover.shift_month(~D[2026-09-15], -1) == {2026, 8}
    end

    test "shifts back across a year boundary" do
      assert Rollover.shift_month(~D[2026-01-15], -1) == {2025, 12}
    end

    test "shifts forward across a year boundary" do
      assert Rollover.shift_month(~D[2026-12-15], 1) == {2027, 1}
    end

    test "a zero offset is a no-op" do
      assert Rollover.shift_month(~D[2026-09-15], 0) == {2026, 9}
    end
  end

  describe "month_name/1" do
    test "maps 1..12 to full English month names" do
      assert Rollover.month_name(1) == "January"
      assert Rollover.month_name(8) == "August"
      assert Rollover.month_name(12) == "December"
    end
  end

  describe "project_name/2" do
    test "joins the prefix, month name, and year" do
      assert Rollover.project_name("PAYMENTS SWAT", {2026, 8}) == "PAYMENTS SWAT August 2026"
    end
  end

  describe "run/2" do
    test "does nothing when last month's project doesn't exist" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => variables} = Jason.decode!(body)
        assert variables["name"] == "PAYMENTS SWAT August 2026"

        Req.Test.json(conn, %{"data" => %{"projects" => %{"nodes" => []}}})
      end)

      assert {:ok, %{source: nil, target: nil, moved: 0}} =
               Rollover.run("PAYMENTS SWAT", ~D[2026-09-15])
    end

    test "moves every open issue from source to target, auto-creating a missing target" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"query" => query, "variables" => variables} = Jason.decode!(body)

        cond do
          String.contains?(query, "projectCreate") ->
            assert variables == %{
                     "input" => %{
                       "name" => "PAYMENTS SWAT September 2026",
                       "teamIds" => ["t1"]
                     }
                   }

            Req.Test.json(conn, %{
              "data" => %{
                "projectCreate" => %{
                  "project" => %{
                    "id" => "p2",
                    "name" => "PAYMENTS SWAT September 2026",
                    "content" => nil,
                    "slugId" => "sept26",
                    "description" => "",
                    "url" => "https://linear.app/x/project/sept-sept26"
                  },
                  "success" => true,
                  "lastSyncId" => 1.0
                }
              }
            })

          String.contains?(query, "projects(filter") &&
              variables["name"] == "PAYMENTS SWAT August 2026" ->
            Req.Test.json(conn, %{
              "data" => %{
                "projects" => %{
                  "nodes" => [
                    %{
                      "id" => "p1",
                      "name" => "PAYMENTS SWAT August 2026",
                      "content" => nil,
                      "slugId" => "aug26",
                      "description" => "",
                      "url" => "https://linear.app/x/project/aug-aug26",
                      "teams" => %{
                        "nodes" => [%{"id" => "t1", "key" => "ENG", "name" => "Engineering"}]
                      }
                    }
                  ]
                }
              }
            })

          String.contains?(query, "projects(filter") &&
              variables["name"] == "PAYMENTS SWAT September 2026" ->
            Req.Test.json(conn, %{"data" => %{"projects" => %{"nodes" => []}}})

          String.contains?(query, "issues(filter") ->
            assert variables["filter"]["project"] == %{"id" => %{"eq" => "p1"}}
            refute Map.has_key?(variables["filter"], "assignee")

            Req.Test.json(conn, %{
              "data" => %{
                "issues" => %{
                  "edges" => [
                    %{
                      "node" => %{
                        "id" => "i1",
                        "identifier" => "PAY-1",
                        "title" => "First",
                        "branchName" => "pay-1-first",
                        "description" => nil,
                        "assignee" => nil,
                        "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
                      },
                      "cursor" => "c1"
                    },
                    %{
                      "node" => %{
                        "id" => "i2",
                        "identifier" => "PAY-2",
                        "title" => "Second",
                        "branchName" => "pay-2-second",
                        "description" => nil,
                        "assignee" => nil,
                        "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
                      },
                      "cursor" => "c2"
                    }
                  ],
                  "pageInfo" => %{"hasNextPage" => false, "endCursor" => "c2"}
                }
              }
            })

          String.contains?(query, "issueUpdate") ->
            assert variables["input"] == %{"projectId" => "p2"}

            Req.Test.json(conn, %{
              "data" => %{
                "issueUpdate" => %{
                  "issue" => %{
                    "id" => variables["id"],
                    "identifier" => variables["id"],
                    "title" => "moved",
                    "branchName" => nil,
                    "description" => nil,
                    "assignee" => nil,
                    "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
                    "comments" => %{"nodes" => []}
                  }
                }
              }
            })
        end
      end)

      assert {:ok, %{source: source, target: target, moved: 2}} =
               Rollover.run("PAYMENTS SWAT", ~D[2026-09-15])

      assert source.id == "p1"
      assert target.id == "p2"
    end
  end
end
