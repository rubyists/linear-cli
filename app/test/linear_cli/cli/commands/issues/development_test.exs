defmodule LinearCli.CLI.Commands.Issues.DevelopmentTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import LinearCli.CLI.IssueCommandsHelpers

  alias LinearCli.CLI.Commands.Issues.Development
  alias LinearCli.Linear.User

  describe "issue develop (Ruby: commands/issue/develop.rb)" do
    test "resolves/self-assigns the issue, checks out its branch, and pulls" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      stub_responses([
        {"issue(id: $id)",
         %{"data" => %{"issue" => issue_map(%{"branchName" => "main", "assignee" => me_map()})}}}
      ])

      result = %{args: %{issue_id: "CRY-1"}}

      output =
        capture_io(fn ->
          assert :ok = Development.issue_develop(result, cwd: repo, me: me)
        end)

      assert output =~ "You are already assigned CRY-1"
      assert output =~ "Checked out branch main"
      assert output =~ "Ready to develop!"
      refute output =~ "Upstream branch not found"
    end

    test "pushes a new branch and sets its upstream when the branch has no tracking branch yet" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      stub_responses([
        {"issue(id: $id)",
         %{
           "data" => %{
             "issue" =>
               issue_map(%{"branchName" => "cry-1-fix-the-thing", "assignee" => me_map()})
           }
         }}
      ])

      result = %{args: %{issue_id: "CRY-1"}}

      output =
        capture_io(fn ->
          assert :ok = Development.issue_develop(result, cwd: repo, me: me)
        end)

      assert output =~ "Checked out branch cry-1-fix-the-thing"
      assert output =~ "Upstream branch not found, pushing local cry-1-fix-the-thing to origin"
      assert output =~ "Set upstream to origin/cry-1-fix-the-thing"
      assert output =~ "Ready to develop!"
    end
  end

  describe "issue pr (Ruby: commands/issue/pr.rb)" do
    test "checks out the issue's branch (no pull/push) and opens a PR via the injectable runner" do
      repo = git_repo!()
      me = %User{id: "u1", name: "Ada", email: "ada@x.com"}

      stub_responses([
        {"issue(id: $id)",
         %{"data" => %{"issue" => issue_map(%{"branchName" => "main", "assignee" => me_map()})}}}
      ])

      result = %{
        args: %{issue_id: "CRY-1"},
        options: %{title: "fix: CRY-1 - Fix the thing", description: "body"}
      }

      output =
        capture_io(fn ->
          assert :ok =
                   Development.issue_pr(result,
                     cwd: repo,
                     me: me,
                     runner: fn title, body -> "gh said: #{title} (#{body})" end
                   )
        end)

      assert output =~ "Checked out branch main"
      assert output =~ "gh said: fix: CRY-1 - Fix the thing (body)"
      refute output =~ "Ready to develop!"
    end
  end

  describe "issue take (Ruby: commands/issue/take.rb)" do
    test "self-assigns unassigned issues and warns, but doesn't abort, on an unknown id" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        query = decoded["query"]
        variables = decoded["variables"] || %{}

        cond do
          query =~ "viewer" ->
            Req.Test.json(conn, %{"data" => %{"viewer" => me_map()}})

          query =~ "issue(id: $id)" and variables["id"] == "CRY-1" ->
            Req.Test.json(conn, %{"data" => %{"issue" => issue_map(%{"assignee" => nil})}})

          query =~ "issue(id: $id)" and variables["id"] == "NOPE" ->
            Req.Test.json(conn, %{"data" => %{"issue" => nil}})

          query =~ "issueUpdate" ->
            Req.Test.json(conn, issue_updated(%{"assignee" => me_map()}))
        end
      end)

      output =
        capture_io(fn ->
          assert :ok = LinearCli.CLI.main(["issue", "take", "CRY-1", "nope"])
        end)

      assert output =~ "Assigning issue CRY-1 to ya"
      assert output =~ "No issue found with id nope"
      assert output =~ "CRY-1"
    end
  end
end
