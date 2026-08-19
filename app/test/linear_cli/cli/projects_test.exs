defmodule LinearCli.CLI.ProjectsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Projects
  alias LinearCli.Linear.Project

  defp project(attrs) do
    struct!(
      %Project{
        id: "id",
        name: "name",
        url: "https://linear.app/x/project/name-abc",
        slug_id: "abc",
        description: ""
      },
      attrs
    )
  end

  describe "project_scores/2 (Ruby: CLI::Projects#project_scores)" do
    test "drops non-matching (score 0) projects" do
      manhattan = project(name: "Manhattan")
      brooklyn = project(name: "Brooklyn")

      assert Projects.project_scores([manhattan, brooklyn], "Manhattan") == [manhattan]
    end

    test "sorts ascending by score, matching Ruby's un-reversed sort_by" do
      partial =
        project(
          id: "1",
          name: "Manhattan Rollout",
          url: "https://linear.app/x/project/manhattan-rollout-a1"
        )

      exact =
        project(
          id: "2",
          name: "Manhattan",
          url: "https://linear.app/x/project/manhattan-a2",
          slug_id: "a2"
        )

      # "Manhattan" is an exact (100) match for `exact` and only a
      # substring (75) match for `partial` - ascending order puts the
      # weaker match first.
      assert Projects.project_scores([partial, exact], "Manhattan") == [partial, exact]
    end

    test "returns an empty list when nothing matches" do
      assert Projects.project_scores([project(name: "Brooklyn")], "Manhattan") == []
    end
  end

  describe "project_for/2 (Ruby: CLI::Projects#project_for) - exact-match paths (no prompting)" do
    test "returns nil without prompting when projects is empty" do
      assert Projects.project_for([], "anything") == nil
    end

    test "returns the sole exact match directly, without prompting" do
      manhattan =
        project(
          id: "1",
          name: "Manhattan",
          url: "https://linear.app/x/project/manhattan-a1",
          slug_id: "a1"
        )

      brooklyn =
        project(
          id: "2",
          name: "Brooklyn",
          url: "https://linear.app/x/project/brooklyn-a2",
          slug_id: "a2"
        )

      assert Projects.project_for([manhattan, brooklyn], "Manhattan") == manhattan
    end

    test "an exact name wins over a weaker substring match" do
      exact = project(id: "1", name: "Wallet Service Extraction")
      partial = project(id: "2", name: "Wallet Service Extraction for Humans")

      assert Projects.project_for([partial, exact], "Wallet Service Extraction") == exact
    end

    test "an exact match by id wins outright even among several candidates" do
      exact = project(id: "abc-123", name: "Something Else")
      other = project(id: "other", name: "Something Else Entirely")

      assert Projects.project_for([exact, other], "abc-123") == exact
    end
  end

  describe "project_for/2 - non-exact/ambiguous paths (fall through to LinearCli.CLI.Prompt.select/2)" do
    test "a lone positive-but-not-exact match still gets offered as the only choice (Owl auto-selects a singleton list)" do
      manhattan =
        project(
          id: "1",
          name: "Manhattan Rollout",
          url: "https://linear.app/x/project/manhattan-rollout-a1"
        )

      assert capture_io(fn ->
               assert Projects.project_for([manhattan], "Manhattan") == manhattan
             end) =~ "Autoselect: Manhattan Rollout"
    end

    test "multiple positive matches with none scoring 100 prompt across just those candidates, in ascending-score order" do
      partial1 = project(id: "1", name: "Manhattan Rollout")
      partial2 = project(id: "2", name: "Manhattan Phase 2")

      output =
        capture_io([input: "2\n"], fn ->
          assert Projects.project_for([partial1, partial2], "Manhattan") == partial2
        end)

      assert output =~ "Project:"
    end
  end

  describe "ask_for_projects/2 (Ruby: CLI::Projects#ask_for_projects)" do
    test "returns the sole project directly without warning or prompting when no search term was given" do
      only = project(name: "Manhattan")

      assert capture_io(fn ->
               assert Projects.ask_for_projects([only], nil) == only
             end) == ""
    end

    test "still warns (but skips the select prompt) when there's a sole project and a search term was given" do
      only = project(name: "Manhattan")

      output =
        capture_io(fn ->
          assert Projects.ask_for_projects([only], "Gotham") == only
        end)

      assert output =~ "No project found matching Gotham."
    end

    test "prompts across every project when there is more than one and no search term" do
      a = project(name: "A")
      b = project(name: "B")

      output =
        capture_io([input: "2\n"], fn ->
          assert Projects.ask_for_projects([a, b], nil) == b
        end)

      refute output =~ "No project found"
      assert output =~ "Project:"
    end
  end
end
