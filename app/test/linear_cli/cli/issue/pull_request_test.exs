defmodule LinearCli.CLI.Issue.PullRequestTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Issue.PullRequest
  alias LinearCli.Linear.{Issue, Team}

  defp issue(attrs \\ %{}) do
    struct!(
      %Issue{
        id: "i1",
        identifier: "CRY-1",
        title: "Fix the thing",
        description: "It is broken",
        team: %Team{id: "t1", key: "ENG", name: "Engineering"}
      },
      attrs
    )
  end

  describe "create_pr!/3 and issue_pr/2" do
    test "create_pr!/3 forwards to the injectable runner" do
      runner = fn title, body -> "ran with #{title}/#{body}" end
      assert PullRequest.create_pr!("My title", "My body", runner) == "ran with My title/My body"
    end

    test "issue_pr/2 resolves title/description then prints the runner's output as a warning" do
      output =
        capture_io(fn ->
          assert :ok =
                   PullRequest.issue_pr(issue(),
                     title: "fix: CRY-1 - Fix the thing",
                     description: "body",
                     runner: fn title, body -> "gh said: #{title} (#{body})" end
                   )
        end)

      assert output =~ "gh said: fix: CRY-1 - Fix the thing (body)"
    end
  end
end
