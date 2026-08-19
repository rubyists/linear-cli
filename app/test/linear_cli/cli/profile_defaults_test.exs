defmodule LinearCli.CLI.ProfileDefaultsTest do
  # Not async: shares LinearCli.Profiles' one sqlite file
  # (config :linear_cli, :profiles_db_path) with LinearCli.ProfilesTest -
  # both async: false, so ExUnit never runs them concurrently with each
  # other or with any async: true module that might otherwise stomp on the
  # same file.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias LinearCli.CLI.{Commands, IssueHelpers}
  alias LinearCli.Linear.User
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

  defp me_map(overrides \\ %{}) do
    Map.merge(
      %{"id" => "u1", "name" => "Ada", "email" => "ada@x.com", "teams" => %{"nodes" => []}},
      overrides
    )
  end

  defp comment_created do
    %{
      "data" => %{"commentCreate" => %{"comment" => %{"id" => "c1", "body" => "x", "url" => "u"}}}
    }
  end

  # Every git-touching test gets a fresh local repo (one commit on "main",
  # already pushed to/tracking a fresh bare "origin") under
  # `System.tmp_dir!()` - never the real project working directory. See
  # `LinearCli.CLI.IssueCommandsTest`'s own identical setup.
  defp git_repo! do
    origin_path = tmp_path("origin")
    File.mkdir_p!(origin_path)
    {_output, 0} = System.cmd("git", ["init", "--bare", "-q"], cd: origin_path)

    repo_path = tmp_path("repo")
    File.mkdir_p!(repo_path)
    {_output, 0} = System.cmd("git", ["init", "-q"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: repo_path)
    File.write!(Path.join(repo_path, "README.md"), "hello")
    {_output, 0} = System.cmd("git", ["add", "README.md"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["commit", "-q", "-m", "init"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["branch", "-M", "main"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["remote", "add", "origin", origin_path], cd: repo_path)
    {_output, 0} = System.cmd("git", ["push", "-q", "-u", "origin", "main"], cd: repo_path)

    on_exit(fn ->
      File.rm_rf!(origin_path)
      File.rm_rf!(repo_path)
    end)

    repo_path
  end

  defp tmp_path(prefix) do
    Path.join(
      System.tmp_dir!(),
      "linear_cli_profile_defaults_test_#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
    )
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
          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map("CRY")}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, team_projects([project_map("p1", "Manhattan Rollout")]))

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
          String.contains?(query, "team(id: $id)") ->
            Req.Test.json(conn, %{"data" => %{"team" => team_map("ENG")}})

          String.contains?(query, "projects(first: 100") ->
            Req.Test.json(conn, team_projects([project_map("p2", "Platform Cleanup")]))

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

    test "--no-profile bypasses the active profile's team/project defaults" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "projects(first: $first") do
          raise "--no-profile must not query projects when --project wasn't given"
        end

        if String.contains?(query, "issues(filter") do
          send(test_pid, {:filter, decoded["variables"]["filter"]})
          Req.Test.json(conn, issues_response([issue_map()]))
        else
          raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        flags: %{no_mine: false, unassigned: false, full: false, no_profile: true},
        options: %{team: nil, project: nil, output: "text"},
        unknown: []
      }

      output = capture_io(fn -> assert :ok = Commands.issue_list(result) end)

      assert output =~ "CRY-1"
      assert_received {:filter, filter}
      refute Map.has_key?(filter, "team")
      refute Map.has_key?(filter, "project")
    end

    test "--no-profile with an explicit --team still applies the explicit team" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "issues(filter") do
          send(test_pid, {:filter, decoded["variables"]["filter"]})
          Req.Test.json(conn, issues_response([issue_map()]))
        else
          raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        flags: %{no_mine: false, unassigned: false, full: false, no_profile: true},
        options: %{team: "ENG", project: nil, output: "text"},
        unknown: []
      }

      capture_io(fn -> assert :ok = Commands.issue_list(result) end)

      assert_received {:filter, filter}
      assert filter["team"] == %{"key" => %{"eq" => "ENG"}}
      refute Map.has_key?(filter, "project")
    end

    test "--no-profile with an explicit --project still applies the explicit project" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY", project: "Manhattan Rollout")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "projects(first: $first") ->
            Req.Test.json(conn, all_projects([project_map("p3", "Platform Cleanup")]))

          String.contains?(query, "issues(filter") ->
            send(test_pid, {:filter, decoded["variables"]["filter"]})
            Req.Test.json(conn, issues_response([issue_map()]))

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        flags: %{no_mine: false, unassigned: false, full: false, no_profile: true},
        options: %{team: nil, project: "Platform Cleanup", output: "text"},
        unknown: []
      }

      capture_io(fn -> assert :ok = Commands.issue_list(result) end)

      assert_received {:filter, filter}
      refute Map.has_key?(filter, "team")
      assert filter["project"] == %{"id" => %{"eq" => "p3"}}
    end

    test "resolves bare issue numbers (positional ids) via the active profile's team" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "issue(id: $id)") do
          send(test_pid, {:id, decoded["variables"]["id"]})
          Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})
        else
          raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        flags: %{no_mine: false, unassigned: false, full: false},
        options: %{team: nil, project: nil, output: "text"},
        unknown: ["42"]
      }

      output = capture_io(fn -> assert :ok = Commands.issue_list(result) end)

      assert output =~ "CRY-1"
      assert_received {:id, "CRY-42"}
    end
  end

  describe "Commands.issue_update/1 resolves bare issue numbers via the active profile" do
    test "expands a bare positional id before looking it up" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")

      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            send(test_pid, {:id, decoded["variables"]["id"]})
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map()}})

          String.contains?(query, "commentCreate") ->
            Req.Test.json(conn, comment_created())

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      result = %{
        unknown: ["42"],
        options: %{comment: "fyi", project: nil, reason: nil},
        flags: %{cancel: false, close: false, trash: false}
      }

      output = capture_io(fn -> assert :ok = Commands.issue_update(result) end)

      assert output =~ "Comment added to CRY-1"
      assert_received {:id, "CRY-42"}
    end
  end

  describe "Commands.issue_develop/2, issue_pr/2, issue_take/2 resolve bare issue numbers via the active profile" do
    test "issue_develop/2 expands the bare issue_id before self-assigning/checking it out" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")

      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "issue(id: $id)") do
          send(test_pid, {:id, decoded["variables"]["id"]})

          Req.Test.json(
            conn,
            %{
              "data" => %{
                "issue" => issue_map(%{"branchName" => "main", "assignee" => me_map()})
              }
            }
          )
        else
          raise "no stub matched query: #{query}"
        end
      end)

      result = %{args: %{issue_id: "42"}}

      output =
        capture_io(fn ->
          assert :ok = Commands.issue_develop(result, cwd: repo, me: me)
        end)

      assert output =~ "Checked out branch main"
      assert_received {:id, "CRY-42"}
    end

    test "issue_pr/2 expands the bare issue_id before self-assigning/checking it out" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")

      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        if String.contains?(query, "issue(id: $id)") do
          send(test_pid, {:id, decoded["variables"]["id"]})

          Req.Test.json(
            conn,
            %{
              "data" => %{
                "issue" => issue_map(%{"branchName" => "main", "assignee" => me_map()})
              }
            }
          )
        else
          raise "no stub matched query: #{query}"
        end
      end)

      result = %{args: %{issue_id: "42"}, options: %{title: "fix: title", description: "body"}}

      output =
        capture_io(fn ->
          assert :ok =
                   Commands.issue_pr(result,
                     cwd: repo,
                     me: me,
                     runner: fn _title, _body -> "https://github.com/x/y/pull/1" end
                   )
        end)

      assert output =~ "Checked out branch main"
      assert_received {:id, "CRY-42"}
    end

    test "issue_take/2 expands every bare id in the batch before self-assigning" do
      {:ok, _} = Profiles.create("manhattan", team: "CRY")
      :ok = Profiles.activate("manhattan")

      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}
      test_pid = self()

      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]

        cond do
          String.contains?(query, "issue(id: $id)") ->
            send(test_pid, {:id, decoded["variables"]["id"]})
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map(%{"assignee" => nil})}})

          String.contains?(query, "issueUpdate") ->
            Req.Test.json(conn, %{
              "data" => %{"issueUpdate" => %{"issue" => issue_map(%{"assignee" => me_map()})}}
            })

          true ->
            raise "no stub matched query: #{query}"
        end
      end)

      result = %{unknown: ["42"], options: %{output: "text"}}

      output =
        capture_io(fn ->
          assert :ok = Commands.issue_take(result, me: me)
        end)

      assert output =~ "Assigning issue CRY-42 to ya"
      assert_received {:id, "CRY-42"}
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

          String.contains?(query, "projects(first: 100") ->
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

          String.contains?(query, "projects(first: 100") ->
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
