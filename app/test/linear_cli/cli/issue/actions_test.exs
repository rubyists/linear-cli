defmodule LinearCli.CLI.Issue.ActionsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Issue.Actions
  alias LinearCli.Linear.{Comment, Issue, Project, Team, WorkflowState}

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

  defp stub_responses(pairs) do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)

      case Enum.find(pairs, fn {match, _resp} -> String.contains?(query, match) end) do
        {_match, response} -> Req.Test.json(conn, response)
        nil -> raise "no stub matched query: #{query}"
      end
    end)
  end

  defp comment_created(id \\ "c1") do
    %{"data" => %{"commentCreate" => %{"comment" => %{"id" => id, "body" => "x", "url" => "u"}}}}
  end

  defp issue_updated(overrides \\ %{}) do
    issue_map =
      Map.merge(
        %{
          "id" => "i1",
          "identifier" => "CRY-1",
          "title" => "Fix the thing",
          "branchName" => "cry-1-fix-the-thing",
          "description" => "It is broken",
          "assignee" => nil,
          "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"},
          "comments" => %{"nodes" => []}
        },
        overrides
      )

    %{"data" => %{"issueUpdate" => %{"issue" => issue_map}}}
  end

  defp workflow_states(states) do
    %{"data" => %{"team" => %{"states" => %{"nodes" => states}}}}
  end

  defp team_projects(projects) do
    %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}
  end

  defp errors(message) do
    %{"errors" => [%{"message" => message}]}
  end

  describe "issue_comment/2 (Ruby: CLI::Issue#issue_comment)" do
    test "adds the comment and prints a confirmation" do
      stub_responses([{"commentCreate", comment_created()}])

      assert capture_io(fn ->
               assert {:ok, %Comment{id: "c1"}} = Actions.issue_comment(issue(), "lgtm")
             end) =~ "Comment added to CRY-1"
    end

    test "propagates the underlying error without printing anything" do
      stub_responses([{"commentCreate", errors("boom")}])

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Unknown{}} = Actions.issue_comment(issue(), "x")
             end) == ""
    end
  end

  describe "cancel_issue/2 (Ruby: CLI::Issue#cancel_issue)" do
    test "comments, resolves the cancelled state, and transitions the issue" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert {:ok, %Issue{identifier: "CRY-1"}} =
                   Actions.cancel_issue(issue(), reason: "no longer needed")
        end)

      assert output =~ "Comment added to CRY-1"
      assert output =~ "CRY-1 was cancelled"
    end

    test "surfaces the smells_bad error instead of attempting the transition" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {", workflow_states([])}
      ])

      assert capture_io(fn ->
               assert {:error, {:smells_bad, _message}} =
                        Actions.cancel_issue(issue(), reason: "no longer needed")
             end) =~ "Comment added to CRY-1"
    end

    test "is a no-op when the issue is already in a cancelled state" do
      already_cancelled =
        issue(%{state: %WorkflowState{id: "s1", name: "Cancelled", type: "cancelled"}})

      output =
        capture_io(fn ->
          assert {:ok, ^already_cancelled} =
                   Actions.cancel_issue(already_cancelled, reason: "no longer needed")
        end)

      assert output =~ "CRY-1 is already Cancelled"
      refute output =~ "Comment added"
    end
  end

  describe "close_issue/2 (Ruby: CLI::Issue#close_issue)" do
    test "closes (completed state) by default" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Done", "position" => 1.0, "type" => "completed"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert {:ok, %Issue{}} = Actions.close_issue(issue(), reason: "shipped")
        end)

      assert output =~ "CRY-1 was closed"
    end

    test "cancels (cancelled state) when opts[:cancel] is truthy" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert {:ok, %Issue{}} =
                   Actions.close_issue(issue(), cancel: true, reason: "nope")
        end)

      assert output =~ "CRY-1 was cancelled"
    end

    test "is a no-op when the issue is already in a completed state" do
      already_done = issue(%{state: %WorkflowState{id: "s1", name: "Done", type: "completed"}})

      output =
        capture_io(fn ->
          assert {:ok, ^already_done} = Actions.close_issue(already_done, reason: "shipped")
        end)

      assert output =~ "CRY-1 is already Done"
      refute output =~ "Comment added"
    end

    test "is a no-op when cancel: true and issue is already in a cancelled state" do
      already_cancelled =
        issue(%{state: %WorkflowState{id: "s1", name: "Cancelled", type: "cancelled"}})

      output =
        capture_io(fn ->
          assert {:ok, ^already_cancelled} =
                   Actions.close_issue(already_cancelled, cancel: true, reason: "nope")
        end)

      assert output =~ "CRY-1 is already Cancelled"
      refute output =~ "Comment added"
    end
  end

  describe "update_description/2" do
    test "resolves and sends the description, printing a confirmation" do
      stub_responses([{"issueUpdate", issue_updated(%{"description" => "New body"})}])

      assert capture_io(fn ->
               assert {:ok, %Issue{description: "New body"}} =
                        Actions.update_description(issue(), "New body")
             end) =~ "CRY-1 description updated"
    end

    test "propagates an API error without printing confirmation" do
      stub_responses([{"issueUpdate", %{"errors" => [%{"message" => "boom"}]}}])

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Invalid{}} =
                        Actions.update_description(issue(), "New body")
             end) == ""
    end
  end

  describe "move_issue/2" do
    test "moves the issue to the resolved project and prints a confirmation" do
      stub_responses([{"issueUpdate", issue_updated()}])

      project = %Project{id: "p1", name: "Manhattan Rollout"}

      assert capture_io(fn ->
               assert {:ok, %Issue{}} = Actions.move_issue(issue(), project)
             end) =~ "CRY-1 was moved to Manhattan Rollout"
    end

    test "propagates an API error without printing confirmation" do
      stub_responses([{"issueUpdate", %{"errors" => [%{"message" => "boom"}]}}])

      project = %Project{id: "p1", name: "Manhattan Rollout"}

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Invalid{}} = Actions.move_issue(issue(), project)
             end) == ""
    end
  end

  describe "attach_project/2 (Ruby: CLI::Issue#attach_project)" do
    test "resolves the project by name against the team's projects and attaches it" do
      stub_responses([
        {"projects(first: 100",
         team_projects([
           %{
             "id" => "p1",
             "name" => "Manhattan Rollout",
             "content" => nil,
             "slugId" => "abc",
             "description" => nil,
             "url" => "https://linear.app/x/project/manhattan-rollout-abc"
           }
         ])},
        {"issueUpdate", issue_updated()}
      ])

      assert capture_io(fn ->
               assert {:ok, %Issue{}} =
                        Actions.attach_project(issue(), "Manhattan Rollout")
             end) =~ "CRY-1 was moved to Manhattan Rollout"
    end
  end

  describe "update_issue/2 dispatch (Ruby: CLI::Issue#update_issue)" do
    test "with :close, comments then closes" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Done", "position" => 1.0, "type" => "completed"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert :ok = Actions.update_issue(issue(), close: true, reason: "done")
        end)

      assert output =~ "CRY-1 was closed"
    end

    test "with :cancel, comments then cancels" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {",
         workflow_states([
           %{"id" => "s1", "name" => "Cancelled", "position" => 1.0, "type" => "cancelled"}
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert :ok = Actions.update_issue(issue(), cancel: true, reason: "nope")
        end)

      assert output =~ "CRY-1 was cancelled"
    end

    test "with :pr, opens a PR via the injectable runner and never calls the API" do
      output =
        capture_io(fn ->
          assert :ok =
                   Actions.update_issue(issue(),
                     pr: true,
                     title: "fix: CRY-1 - Fix the thing",
                     description: "body",
                     runner: fn _title, _body -> "https://github.com/x/y/pull/1" end
                   )
        end)

      assert output =~ "https://github.com/x/y/pull/1"
    end

    test "with :project, resolves and attaches" do
      stub_responses([
        {"projects(first: 100",
         team_projects([
           %{
             "id" => "p1",
             "name" => "Manhattan Rollout",
             "content" => nil,
             "slugId" => "abc",
             "description" => nil,
             "url" => "https://linear.app/x/project/manhattan-rollout-abc"
           }
         ])},
        {"issueUpdate", issue_updated()}
      ])

      output =
        capture_io(fn ->
          assert :ok = Actions.update_issue(issue(), project: "Manhattan Rollout")
        end)

      assert output =~ "CRY-1 was moved to Manhattan Rollout"
    end

    test "with :description, updates the issue description" do
      stub_responses([{"issueUpdate", issue_updated(%{"description" => "New body"})}])

      output =
        capture_io(fn ->
          assert :ok = Actions.update_issue(issue(), description: "New body")
        end)

      assert output =~ "CRY-1 description updated"
    end

    test "with only :comment, comments and stops without the 'no action taken' warning" do
      stub_responses([{"commentCreate", comment_created()}])

      output =
        capture_io(fn ->
          assert :ok = Actions.update_issue(issue(), comment: "fyi")
        end)

      assert output =~ "Comment added to CRY-1"
      refute output =~ "No action taken"
    end

    test "with no options at all, warns and reports no update, without calling the API" do
      output =
        capture_io(fn ->
          assert :ok = Actions.update_issue(issue())
        end)

      assert output =~ "No action taken, no options specified"
      assert output =~ "Issue was not updated"
    end

    test "an error from a dispatched action propagates as {:error, reason}" do
      stub_responses([
        {"commentCreate", comment_created()},
        {"states {", errors("boom")}
      ])

      assert capture_io(fn ->
               assert {:error, %Ash.Error.Unknown{}} =
                        Actions.update_issue(issue(), close: true, reason: "x")
             end) =~ "Comment added to CRY-1"
    end
  end
end
