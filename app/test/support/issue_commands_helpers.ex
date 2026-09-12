defmodule LinearCli.CLI.IssueCommandsHelpers do
  @moduledoc false

  # Dispatches to one of `pairs` ({substring, response_map}) based on which
  # substring appears in the outgoing GraphQL document.
  def stub_responses(pairs) do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)

      case Enum.find(pairs, fn {match, _resp} -> String.contains?(query, match) end) do
        {_match, response} -> Req.Test.json(conn, response)
        nil -> raise "no stub matched query: #{query}"
      end
    end)
  end

  def team_map, do: %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}

  def me_map(overrides \\ %{}) do
    Map.merge(
      %{"id" => "u1", "name" => "Ada", "email" => "ada@x.com", "teams" => %{"nodes" => []}},
      overrides
    )
  end

  def label_response(names) do
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

  def project_map(id, name) do
    %{
      "id" => id,
      "name" => name,
      "content" => nil,
      "slugId" => "abc",
      "description" => nil,
      "url" => "https://linear.app/x/project/#{id}"
    }
  end

  def team_projects(projects),
    do: %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}

  def issue_map(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "i1",
        "identifier" => "CRY-1",
        "title" => "Fix the thing",
        "branchName" => "cry-1-fix-the-thing",
        "description" => "It is broken",
        "assignee" => nil,
        "state" => %{"id" => "s1", "name" => "In Progress", "type" => "started"},
        "team" => team_map(),
        "comments" => %{"nodes" => []}
      },
      overrides
    )
  end

  def issue_updated(overrides \\ %{}) do
    %{"data" => %{"issueUpdate" => %{"issue" => issue_map(overrides)}}}
  end

  def comment_created do
    %{
      "data" => %{"commentCreate" => %{"comment" => %{"id" => "c1", "body" => "x", "url" => "u"}}}
    }
  end

  def workflow_states(states) do
    %{"data" => %{"team" => %{"states" => %{"nodes" => states}}}}
  end

  # Workspace-wide (not team-scoped) projects query shape.
  def all_projects(projects) do
    %{
      "data" => %{
        "projects" => %{
          "edges" => Enum.map(projects, &%{"node" => &1, "cursor" => &1["id"]}),
          "pageInfo" => %{"hasNextPage" => false}
        }
      }
    }
  end

  def issues_response(issues) do
    %{
      "data" => %{
        "issues" => %{
          "edges" => Enum.map(issues, &%{"node" => &1, "cursor" => &1["id"]}),
          "pageInfo" => %{"hasNextPage" => false}
        }
      }
    }
  end

  def tmp_path(prefix) do
    Path.join(
      System.tmp_dir!(),
      "linear_cli_issue_commands_test_#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
    )
  end

  # Every git-touching test gets a fresh local repo (one commit on "main",
  # already pushed to/tracking a fresh bare "origin") under
  # `System.tmp_dir!()` - never the real project working directory. See house
  # rule 6 and `LinearCli.GitTest`'s own identical setup.
  def git_repo! do
    origin_path = tmp_dir!("origin")
    {_output, 0} = System.cmd("git", ["init", "--bare", "-q"], cd: origin_path)

    repo_path = tmp_dir!("repo")
    {_output, 0} = System.cmd("git", ["init", "-q"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: repo_path)
    File.write!(Path.join(repo_path, "README.md"), "hello")
    {_output, 0} = System.cmd("git", ["add", "README.md"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["commit", "-q", "-m", "init"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["branch", "-M", "main"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["remote", "add", "origin", origin_path], cd: repo_path)
    {_output, 0} = System.cmd("git", ["push", "-q", "-u", "origin", "main"], cd: repo_path)

    repo_path
  end

  # `System.unique_integer/1` resets across BEAM VM restarts, so an interrupted
  # prior run can reuse a stale /tmp directory. A cryptographic nonce avoids
  # collisions across processes; `on_exit` is registered before any git command
  # so a setup failure still cleans up.
  def tmp_dir!(prefix) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "linear_cli_issue_commands_test_#{prefix}_#{nonce}")
    File.mkdir!(path)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
