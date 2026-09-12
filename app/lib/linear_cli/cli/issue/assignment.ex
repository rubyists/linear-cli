defmodule LinearCli.CLI.Issue.Assignment do
  @moduledoc """
  Issue self-assignment with optional workflow-state transition.

  Extracted from the former `LinearCli.CLI.IssueHelpers`. The single public
  function, `gimme_da_issue!/2`, looks up an issue by identifier and
  self-assigns it to the current user, unless already assigned. Accepts an
  optional `--status` option (or an already-resolved `:state_id`) to
  simultaneously transition the issue's workflow state.

  Reuses `LinearCli.CLI.Issue.Identifiers.expand_issue_id/1` for bare-ID
  expansion and `LinearCli.CLI.Issue.WorkflowStates.resolve_workflow_state/2`
  for status-name matching, keeping the shared logic in one place.

  Ported from `CLI::Issue#gimme_da_issue!`.

  ## Return convention

  Returns `{:ok, issue}` on success or `{:error, reason}` on failure (never
  raises). User-visible failures use `{:error, {:smells_bad, message}}`.
  """

  alias LinearCli.CLI.Issue.{Identifiers, WorkflowStates}
  alias LinearCli.CLI.Prompt
  alias LinearCli.Linear

  @doc """
  Looks up `issue_id` and self-assigns it to the caller, unless it's already
  assigned to them.

  `opts[:me]` overrides the caller lookup (this port's stand-in for Ruby's
  `me: Rubyists::Linear::User.me` keyword default) - real callers omit it
  and get `LinearCli.Linear.me/0`; tests pass it to avoid stubbing the
  `viewer` query too.

  `opts[:status]` accepts a case-insensitive exact or unique-prefix workflow
  state name to transition the issue at the same time as assignment.
  `opts[:state_id]` accepts an already-resolved state ID directly.

  Ported from `CLI::Issue#gimme_da_issue!`.
  """
  @spec gimme_da_issue!(String.t(), keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def gimme_da_issue!(issue_id, opts \\ []) do
    issue_id = Identifiers.expand_issue_id(issue_id)
    status_opt = parse_status_opt(opts)

    with {:ok, me} <- resolve_me(opts),
         {:ok, [issue]} <- Linear.issues(%{ids: [issue_id]}),
         {:ok, state_id} <- resolve_status_for_issue(issue, status_opt) do
      assign_or_confirm(issue, me, issue_id, state_id)
    end
  end

  defp parse_status_opt(opts) do
    case Keyword.fetch(opts, :state_id) do
      {:ok, id} -> {:resolved, id}
      :error -> {:name, Keyword.get(opts, :status)}
    end
  end

  defp resolve_status_for_issue(_issue, {:resolved, id}), do: {:ok, id}
  defp resolve_status_for_issue(_issue, {:name, nil}), do: {:ok, nil}

  defp resolve_status_for_issue(issue, {:name, name}) do
    with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id) do
      case WorkflowStates.resolve_workflow_state(states, name) do
        {:ok, state} -> {:ok, state.id}
        error -> error
      end
    end
  end

  defp assign_or_confirm(%{assignee: %{id: id}} = issue, %{id: id}, issue_id, nil) do
    Prompt.say("You are already assigned #{issue_id}")
    {:ok, issue}
  end

  defp assign_or_confirm(issue, me, issue_id, state_id) do
    Prompt.say("Assigning issue #{issue_id} to ya")
    Linear.assign_issue(issue, me.id, %{state_id: state_id})
  end

  defp resolve_me(opts) do
    case Keyword.fetch(opts, :me) do
      {:ok, me} -> {:ok, me}
      :error -> Linear.me()
    end
  end
end
