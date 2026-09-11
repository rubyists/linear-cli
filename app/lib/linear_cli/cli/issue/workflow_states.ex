defmodule LinearCli.CLI.Issue.WorkflowStates do
  @moduledoc """
  Workflow-state selection and status-name matching for issue lifecycle
  commands.

  Extracted from `LinearCli.CLI.IssueHelpers`. Provides two entry points for
  type-filtered state selection (`cancelled_state_for/2`,
  `completed_state_for/2`) and one shared entry point for arbitrary
  name/prefix matching (`resolve_workflow_state/2`), which is also called
  directly by `LinearCli.CLI.IssueHelpers.gimme_da_issue!/2` to resolve the
  `--status` option without duplicating the matching logic.

  ## Return shapes

  All public functions return `{:ok, result} | {:error, term()}`.
  `{:error, {:smells_bad, message}}` is returned for user-visible failures
  (no matching state, ambiguous prefix, unknown status name) — the same
  tagged-tuple convention as `LinearCli.CLI.IssueHelpers`.

  ## State selection / prompt behavior

  - A single matching state is returned directly without prompting.
  - Multiple matching states with no `status` argument prompt the user via
    `LinearCli.CLI.Prompt.select/2`.
  - A `status` argument bypasses the prompt and resolves by exact
    case-insensitive name or unique prefix.
  """

  alias LinearCli.CLI.Prompt
  alias LinearCli.Linear

  @doc """
  Resolves `issue`'s team's cancelled workflow state.

  When `status` is `nil`, returns the sole cancelled state directly or prompts
  among several. When `status` is given, selects by case-insensitive exact name
  or unique prefix instead.

  Returns `{:error, {:smells_bad, message}}` if the team has no cancelled-type
  workflow state.

  Ported from the combination of Ruby's `BaseModel#cancelled_states` and
  `CLI::WhatFor#cancelled_state_for`.
  """
  @spec cancelled_state_for(%Linear.Issue{}, String.t() | nil) ::
          {:ok, %Linear.WorkflowState{}} | {:error, term()}
  def cancelled_state_for(issue, status \\ nil),
    do: workflow_state_for(issue, ["cancelled", "canceled"], "cancelled", status)

  @doc """
  Resolves `issue`'s team's completed workflow state.

  When `status` is `nil`, returns the sole completed state directly or prompts
  among several. When `status` is given, selects by case-insensitive exact name
  or unique prefix instead.

  Returns `{:error, {:smells_bad, message}}` if the team has no completed-type
  workflow state.

  Ported from the combination of Ruby's `BaseModel#completed_states` and
  `CLI::WhatFor#completed_state_for`.
  """
  @spec completed_state_for(%Linear.Issue{}, String.t() | nil) ::
          {:ok, %Linear.WorkflowState{}} | {:error, term()}
  def completed_state_for(issue, status \\ nil),
    do: workflow_state_for(issue, ["completed"], "completed", status)

  @doc """
  Resolves a workflow state from `states` by case-insensitive exact `name`
  match, falling back to a unique prefix match if no exact match is found.

  Returns `{:ok, state}` for an unambiguous match, or
  `{:error, {:smells_bad, message}}` for zero matches (unknown status) or
  multiple prefix matches (ambiguous status).

  Public so that callers outside this module (e.g.
  `LinearCli.CLI.IssueHelpers.gimme_da_issue!/2` resolving `--status`) can
  use the same matching logic without duplicating it.
  """
  @spec resolve_workflow_state([%Linear.WorkflowState{}], String.t()) ::
          {:ok, %Linear.WorkflowState{}} | {:error, term()}
  def resolve_workflow_state(states, name) do
    normalized = String.downcase(name)

    states
    |> Enum.filter(&(String.downcase(&1.name) == normalized))
    |> use_prefix_state_matches_if_empty(states, normalized)
    |> resolve_workflow_state_matches(states, name)
  end

  defp workflow_state_for(issue, types, label, status) do
    with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id) do
      states
      |> Enum.filter(&(&1.type in types))
      |> select_workflow_state(issue, label, status)
    end
  end

  defp select_workflow_state([], issue, label, _status) do
    smells_bad("No #{label} workflow states found for team #{issue.team.key || issue.team.id}")
  end

  defp select_workflow_state([state], _issue, _label, nil), do: {:ok, state}

  defp select_workflow_state(states, _issue, label, nil) do
    {:ok, Prompt.select("Choose a #{label} state", Enum.map(states, &{&1.name, &1}))}
  end

  defp select_workflow_state(states, _issue, _label, status) do
    resolve_workflow_state(states, status)
  end

  defp use_prefix_state_matches_if_empty([], states, name) do
    Enum.filter(states, &String.starts_with?(String.downcase(&1.name), name))
  end

  defp use_prefix_state_matches_if_empty(matches, _states, _name), do: matches

  defp resolve_workflow_state_matches([state], _states, _name), do: {:ok, state}

  defp resolve_workflow_state_matches([], states, name) do
    available = Enum.map_join(states, ", ", & &1.name)
    smells_bad("Unknown status #{inspect(name)}. Available: #{available}")
  end

  defp resolve_workflow_state_matches(matches, _states, name) do
    ambiguous = Enum.map_join(matches, ", ", & &1.name)
    smells_bad("Ambiguous status #{inspect(name)}: matches #{ambiguous}")
  end

  defp smells_bad(message), do: {:error, {:smells_bad, message}}
end
