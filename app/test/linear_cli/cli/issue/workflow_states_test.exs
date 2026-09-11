defmodule LinearCli.CLI.Issue.WorkflowStatesTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Issue.WorkflowStates
  alias LinearCli.Linear.{Issue, Team, WorkflowState}

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

  defp stub_states(states) do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"team" => %{"states" => %{"nodes" => states}}}})
    end)
  end

  defp state(id, name, type) do
    %{"id" => id, "name" => name, "position" => 1.0, "type" => type}
  end

  describe "cancelled_state_for/2" do
    test "returns the sole cancelled state directly, no prompt" do
      stub_states([
        state("s1", "Cancelled", "cancelled"),
        state("s2", "Done", "completed")
      ])

      assert capture_io(fn ->
               assert {:ok, %WorkflowState{id: "s1"}} =
                        WorkflowStates.cancelled_state_for(issue())
             end) == ""
    end

    test "also matches the American 'canceled' spelling" do
      stub_states([state("s1", "Canceled", "canceled")])

      assert {:ok, %WorkflowState{id: "s1"}} = WorkflowStates.cancelled_state_for(issue())
    end

    test "prompts to disambiguate when several cancelled states exist and status is nil" do
      stub_states([
        state("s1", "Cancelled", "cancelled"),
        state("s2", "Voided", "cancelled")
      ])

      output =
        capture_io([input: "2\n"], fn ->
          assert {:ok, %WorkflowState{id: "s2"}} = WorkflowStates.cancelled_state_for(issue())
        end)

      assert output =~ "Choose a cancelled state"
    end

    test "selects by status name instead of prompting when status is given" do
      stub_states([
        state("s1", "Cancelled", "cancelled"),
        state("s2", "Voided", "cancelled")
      ])

      assert capture_io(fn ->
               assert {:ok, %WorkflowState{id: "s2"}} =
                        WorkflowStates.cancelled_state_for(issue(), "Voided")
             end) == ""
    end

    test "returns a smells_bad error when the team has no cancelled-type state" do
      stub_states([state("s1", "Backlog", "backlog")])

      assert {:error, {:smells_bad, message}} = WorkflowStates.cancelled_state_for(issue())
      assert message =~ "No cancelled workflow states found for team ENG"
    end
  end

  describe "completed_state_for/2" do
    test "returns the sole completed state directly, no prompt" do
      stub_states([
        state("s1", "Cancelled", "cancelled"),
        state("s2", "Done", "completed")
      ])

      assert capture_io(fn ->
               assert {:ok, %WorkflowState{id: "s2"}} =
                        WorkflowStates.completed_state_for(issue())
             end) == ""
    end

    test "prompts to disambiguate when several completed states exist and status is nil" do
      stub_states([
        state("s1", "Done", "completed"),
        state("s2", "Shipped", "completed")
      ])

      output =
        capture_io([input: "2\n"], fn ->
          assert {:ok, %WorkflowState{id: "s2"}} = WorkflowStates.completed_state_for(issue())
        end)

      assert output =~ "Choose a completed state"
    end

    test "returns a smells_bad error when the team has no completed-type state" do
      stub_states([state("s1", "Backlog", "backlog")])

      assert {:error, {:smells_bad, message}} = WorkflowStates.completed_state_for(issue())
      assert message =~ "No completed workflow states found for team ENG"
    end
  end

  describe "resolve_workflow_state/2" do
    defp states do
      [
        %WorkflowState{id: "s1", name: "Todo", type: "unstarted"},
        %WorkflowState{id: "s2", name: "In Progress", type: "started"},
        %WorkflowState{id: "s3", name: "Done", type: "completed"}
      ]
    end

    test "exact match (case-insensitive) returns the state" do
      assert {:ok, %WorkflowState{id: "s2"}} =
               WorkflowStates.resolve_workflow_state(states(), "in progress")
    end

    test "exact match is case-insensitive" do
      assert {:ok, %WorkflowState{id: "s1"}} =
               WorkflowStates.resolve_workflow_state(states(), "TODO")
    end

    test "unique prefix match returns the state when no exact match exists" do
      assert {:ok, %WorkflowState{id: "s2"}} =
               WorkflowStates.resolve_workflow_state(states(), "In")
    end

    test "unknown name returns a smells_bad error listing available states" do
      assert {:error, {:smells_bad, message}} =
               WorkflowStates.resolve_workflow_state(states(), "NoSuch")

      assert message =~ "Unknown status"
      assert message =~ "NoSuch"
      assert message =~ "Todo"
    end

    test "ambiguous prefix returns a smells_bad error listing the matches" do
      ambiguous_states = [
        %WorkflowState{id: "s1", name: "In Progress", type: "started"},
        %WorkflowState{id: "s2", name: "In Review", type: "started"}
      ]

      assert {:error, {:smells_bad, message}} =
               WorkflowStates.resolve_workflow_state(ambiguous_states, "In")

      assert message =~ "Ambiguous status"
      assert message =~ "In Progress"
      assert message =~ "In Review"
    end
  end
end
