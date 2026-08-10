defmodule LinearCli.CLI.ProfileDefaultsTest do
  # Not async: shares LinearCli.Profiles' one sqlite file
  # (config :linear_cli, :profiles_db_path) with LinearCli.ProfilesTest -
  # both async: false, so ExUnit never runs them concurrently with each
  # other or with any async: true module that might otherwise stomp on the
  # same file.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias LinearCli.CLI.{Commands, IssueHelpers}
  alias LinearCli.Profiles

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)
    :ok
  end

  defp team_map(key), do: %{"id" => "t1", "key" => key, "name" => "Team #{key}"}

  defp project_map(id, name) do
    %{
      "id" => id,
      "name" => name,
      "content" => nil,
      "slugId" => "abc",
      "description" => nil,
      "url" => "https://linear.app/x/project/#{id}"
    }
  end

  defp all_projects(projects) do
    %{
      "data" => %{
        "projects" => %{
          "edges" => Enum.map(projects, &%{"node" => &1, "cursor" => &1["id"]}),
          "pageInfo" => %{"hasNextPage" => false}
        }
      }
    }
  end

  defp team_projects(projects),
    do: %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}

  defp label_response(names) do
    %{
      "data" => %{
        "issueLabels" => %{
          "edges" =>
            Enum.map(names, fn name ->
              %{
                "node" => %{
                  "id" => "l-#{name}",
                  "name" => name,
                  "description" => nil,
                  "isGroup" => false
                }
              }
            end)
        }
      }
    }
  end

  defp issue_map(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "i1",
        "identifier" => "CRY-1",
        "title" => "Fix the thing",
        "branchName" => "cry-1-fix-the-thing",
        "description" => "It is broken",
        "assignee" => nil,
        "team" => team_map("ENG"),
        "comments" => %{"nodes" => []}
      },
      overrides
    )
  end

  defp issues_response(issues) do
    %{
      "data" => %{
        "issues" => %{
          "edges" => Enum.map(issues, &%{"node" => &1, "cursor" => &1["id"]}),
          "pageInfo" => %{"hasNextPage" => false}
        }
      }
    }
  end

  describe "Commands.issue_list/1 falls back to the active profile" do
    test "uses the active profile's team/project when both flags are omitted" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

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

      result = %{
        flags: %{no_mine: false, unassigned: false, full: false},
        options: %{team: nil, project: nil, output: "text"},
        unknown: []
      }

      output = capture_io(fn -> assert :ok = Commands.issue_list(result) end)

      assert output =~ "CRY-1"
      assert_received {:filter, filter}
      assert filter["team"] == %{"key" => %{"eq" => "CRY"}}
      assert filter["project"] == %{"id" => %{"eq" => "p1"}}
    end

    test "an explicit --team/--project still wins over the active profile" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "projects(first: $first") ->
            Req.Test.json(conn, all_projects([project_map("p2", "Platform Cleanup")]))

          String.contains?(query, "issues(filter") ->
            send(test_pid, {:filter, decoded["variables"]["filter"]})
            Req.Test.json(conn, issues_response([issue_map()]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        flags: %{no_mine: false, unassigned: false, full: false},
        options: %{team: "ENG", project: "Platform Cleanup", output: "text"},
        unknown: []
      }

      capture_io(fn -> assert :ok = Commands.issue_list(result) end)

      assert_received {:filter, filter}
      assert filter["team"] == %{"key" => %{"eq" => "ENG"}}
      assert filter["project"] == %{"id" => %{"eq" => "p2"}}
    end
  end

  describe "IssueHelpers.make_da_issue!/1 falls back to the active profile" do
    test "uses the active profile's team/project when both are omitted from opts" do
      {:ok, _} = Profiles.create("manhattan", team: "ENG", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]
        variables = decoded["variables"] || %{}

        cond do
          String.contains?(query, "team(id: $id)") ->
            send(test_pid, {:team_key, variables["id"]})
            Req.Test.json(conn, %{"data" => %{"team" => team_map("ENG")}})

          String.contains?(query, "issueLabels") ->
            Req.Test.json(conn, label_response(["urgent"]))

          String.contains?(query, "projects(first: 100)") ->
            Req.Test.json(conn, team_projects([project_map("p1", "Manhattan Rollout")]))

          String.contains?(query, "issueCreate") ->
            Req.Test.json(conn, %{
              "data" => %{
                "issueCreate" => %{
                  "issue" => issue_map(%{"id" => "i2", "identifier" => "CRY-2"})
                }
              }
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      assert capture_io(fn ->
               assert {:ok, %{identifier: "CRY-2"}} =
                        IssueHelpers.make_da_issue!(
                          title: "New thing",
                          description: "Some description",
                          labels: ["urgent"]
                        )
             end) == ""

      assert_received {:team_key, "ENG"}
    end

    test "an explicit :team still wins over the active profile" do
      {:ok, _} = Profiles.create("manhattan", team: "ENG", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]
        variables = decoded["variables"] || %{}

        cond do
          String.contains?(query, "team(id: $id)") ->
            send(test_pid, {:team_key, variables["id"]})
            Req.Test.json(conn, %{"data" => %{"team" => team_map("PLATFORM")}})

          String.contains?(query, "issueLabels") ->
            Req.Test.json(conn, label_response(["urgent"]))

          String.contains?(query, "projects(first: 100)") ->
            Req.Test.json(conn, team_projects([]))

          String.contains?(query, "issueCreate") ->
            Req.Test.json(conn, %{
              "data" => %{
                "issueCreate" => %{
                  "issue" => issue_map(%{"id" => "i2", "identifier" => "CRY-2"})
                }
              }
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      capture_io(fn ->
        IssueHelpers.make_da_issue!(
          title: "New thing",
          description: "Some description",
          labels: ["urgent"],
          team: "PLATFORM"
        )
      end)

      assert_received {:team_key, "PLATFORM"}
    end
  end
end
