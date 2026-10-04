defmodule LinearCli.CLI.Issue.Actions do
  @moduledoc """
  Issue lifecycle mutations — comment, close/cancel, description update,
  project attachment/move, and update-dispatch — for an already-loaded issue.

  Extracted from the former `LinearCli.CLI.IssueHelpers`. Ported originally from
  `Rubyists::Linear::CLI::Issue`
  (vendor/ruby-linear-cli/lib/linear/commands/issue.rb): `issue_comment`,
  `cancel_issue`, `close_issue`, `attach_project`, `update_issue`.

  ## Return convention

  Every public function returns `{:ok, result}` or `{:error, reason}` (never
  raises), *except* `update_issue/2`, which normalizes down to
  `:ok | {:error, reason}` to match `LinearCli.CLI.run/3`'s command-handler
  contract.

  `reason` is either whatever `LinearCli.Api`/an Ash manual action surfaces
  (a transport/GraphQL/validation error), or a tagged tuple for user-visible
  failures:

      {:error, {:smells_bad, message}}

  where `message` is a human-readable `String.t()`.

  ## Workflow-state resolution

  `cancel_issue/2` and `close_issue/2` delegate to
  `LinearCli.CLI.Issue.WorkflowStates` for cancelled/completed state
  selection. See that module for the full selection and prompt behavior.

  ## PR dispatch

  `update_issue/2` dispatches to `LinearCli.CLI.Issue.PullRequest.issue_pr/2`
  for the `:pr` option.
  """

  alias LinearCli.CLI.Issue.{PullRequest, WorkflowStates}
  alias LinearCli.CLI.{Output, Projects, Prompt, WhatFor}
  alias LinearCli.Linear

  @doc """
  Adds a comment to `issue`, resolving `comment` (asking, or opening an
  editor, if not already given - via `LinearCli.CLI.WhatFor.comment_for/2`)
  first.

  Ported from `CLI::Issue#issue_comment`.
  """
  @spec issue_comment(%Linear.Issue{}, String.t() | nil) ::
          {:ok, %Linear.Comment{}} | {:error, term()}
  def issue_comment(issue, comment), do: issue_comment(issue, comment, [])

  def issue_comment(issue, comment, opts) do
    body = WhatFor.comment_for(issue, comment)

    case Linear.add_comment(issue.identifier, body) do
      {:ok, created} ->
        Output.status(:ok, "Comment added to #{issue.identifier}", opts)
        {:ok, created}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancels `issue`: comments with a resolved reason, then transitions it to
  its team's cancelled workflow state.

  `opts` (Ruby's `**options`, plus this port's `:status`):

    * `:reason` - passed through to `LinearCli.CLI.WhatFor.reason_for/2`
    * `:status` - cancelled workflow state name (exact or unique prefix)
    * `:trash` - trashes the transitioned issue through `issueArchive`

  Ported from `CLI::Issue#cancel_issue`.
  """
  @spec cancel_issue(%Linear.Issue{}, keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def cancel_issue(issue, opts \\ []) do
    if issue.state && issue.state.type in ["cancelled", "canceled"] do
      Output.status(:ok, "#{issue.identifier} is already #{issue.state.name}", opts)
      {:ok, issue}
    else
      reason =
        WhatFor.reason_for(opts[:reason], four: "cancelling #{issue.identifier} - #{issue.title}")

      with {:ok, _comment} <- issue_comment(issue, reason, opts),
           {:ok, cancel_state} <- WorkflowStates.cancelled_state_for(issue, opts[:status]),
           {:ok, updated} <- Linear.close_issue(issue, cancel_state.id, %{trash: !!opts[:trash]}) do
        Output.status(:ok, "#{issue.identifier} was cancelled", opts)
        {:ok, updated}
      end
    end
  end

  @doc """
  Closes (or, if `opts[:cancel]` is truthy, cancels) `issue`: comments with
  a resolved reason, then transitions it to the appropriate workflow state.

  `opts` (Ruby's `**options`, plus this port's `:status`): `:cancel`,
  `:reason`, `:status`, `:trash` - same meaning as `cancel_issue/2`'s.

  Ported from `CLI::Issue#close_issue`. Note this has its own internal
  cancelled/completed branch (mirroring Ruby exactly) even though
  `update_issue/2` never actually reaches it with `opts[:cancel]` truthy -
  `update_issue/2` dispatches to `cancel_issue/2` directly for that case,
  the same as Ruby does.
  """
  @spec close_issue(%Linear.Issue{}, keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def close_issue(issue, opts \\ []) do
    cancelled = opts[:cancel]
    target_types = if cancelled, do: ["cancelled", "canceled"], else: ["completed"]
    done = if cancelled, do: "cancelled", else: "closed"

    if issue.state && issue.state.type in target_types do
      Output.status(:ok, "#{issue.identifier} is already #{issue.state.name}", opts)
      {:ok, issue}
    else
      doing = if cancelled, do: "cancelling", else: "closing"

      reason =
        WhatFor.reason_for(opts[:reason], four: "#{doing} *#{issue.identifier} - #{issue.title}*")

      with {:ok, _comment} <- issue_comment(issue, reason, opts),
           {:ok, workflow_state} <- state_for(cancelled, issue, opts[:status]),
           {:ok, updated} <-
             Linear.close_issue(issue, workflow_state.id, %{trash: !!opts[:trash]}) do
        Output.status(:ok, "#{issue.identifier} was #{done}", opts)
        {:ok, updated}
      end
    end
  end

  defp state_for(true, issue, status), do: WorkflowStates.cancelled_state_for(issue, status)
  defp state_for(_cancelled, issue, status), do: WorkflowStates.completed_state_for(issue, status)

  @doc """
  Moves `issue` to the already-resolved `project`, calling
  `LinearCli.Linear.attach_issue_to_project/2` and printing a confirmation.

  This function takes a pre-resolved `%LinearCli.Linear.Project{}` struct.
  Callers that need to resolve a search string first use `attach_project/3`.
  """
  @spec move_issue(%Linear.Issue{}, %Linear.Project{}) ::
          {:ok, %Linear.Issue{}} | {:error, term()}
  def move_issue(issue, project) do
    case Linear.attach_issue_to_project(issue, project.id) do
      {:ok, updated} ->
        Prompt.ok("#{issue.identifier} was moved to #{project.name}")
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Attaches `issue` to a project matched against `project_search` among the
  projects for the team.

  `opts` controls the output mode. JSON mode uses
  `LinearCli.CLI.Projects.project_for_strict/2`, which returns a project only
  for an exact match. Text mode uses `project_for/2`, which can prompt to
  disambiguate a match.

  If project resolution returns `nil`, this function returns a tagged error.
  Otherwise, it calls `LinearCli.Linear.attach_issue_to_project/2` directly and
  reports successful status through `LinearCli.CLI.Output.status/3`.

  Ported from `CLI::Issue#attach_project`.
  """
  @spec attach_project(%Linear.Issue{}, String.t() | nil, keyword()) ::
          {:ok, %Linear.Issue{}} | {:error, term()}
  def attach_project(issue, project_search, opts \\ []) do
    with {:ok, projects} <-
           Linear.projects_by_team(issue.team.id, %{search: project_search}) do
      project =
        if Output.json?(opts) do
          Projects.project_for_strict(projects, project_search)
        else
          Projects.project_for(projects, project_search)
        end

      if project do
        case Linear.attach_issue_to_project(issue, project.id) do
          {:ok, updated} ->
            Output.status(:ok, "#{issue.identifier} was moved to #{project.name}", opts)
            {:ok, updated}

          {:error, reason} ->
            {:error, reason}
        end
      else
        message =
          if Output.json?(opts) do
            "JSON output requires an exact project match for #{inspect(project_search)}"
          else
            "No project found matching #{project_search}"
          end

        {:error, {:smells_bad, message}}
      end
    end
  end

  @doc """
  Updates `issue`'s description to `description_input`, resolving it (asking,
  or opening an editor, if not already given - via
  `LinearCli.CLI.WhatFor.description_for/1`) first.
  """
  @spec update_description(%Linear.Issue{}, String.t() | nil) ::
          {:ok, %Linear.Issue{}} | {:error, term()}
  def update_description(issue, description_input, opts \\ []) do
    description = WhatFor.description_for(description_input)

    case Linear.update_issue_description(issue, description) do
      {:ok, updated} ->
        Output.status(:ok, "#{issue.identifier} description updated", opts)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sets `issue`'s priority to `priority_value` (0–4, already validated and
  converted by the CLI parser).

  0 = No priority, 1 = Urgent, 2 = High, 3 = Medium, 4 = Low.
  """
  @spec set_priority(%Linear.Issue{}, non_neg_integer()) ::
          {:ok, %Linear.Issue{}} | {:error, term()}
  def set_priority(issue, priority_value, opts \\ []) do
    case Linear.set_issue_priority(issue, priority_value) do
      {:ok, updated} ->
        Output.status(:ok, "#{issue.identifier} priority updated", opts)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Dispatches an issue update per whichever of `opts`' keys is set, in Ruby's
  exact precedence order:

    1. `:comment` - always applied first (via `issue_comment/2`) if given,
       regardless of anything else
    2. `:close` -> `close_issue/2`
    3. `:cancel` -> `cancel_issue/2`
    4. `:pr` -> `LinearCli.CLI.Issue.PullRequest.issue_pr/2`
    5. `:project` -> `attach_project/3`
    6. `:description` -> `update_description/2`
    7. `:priority` -> `set_priority/2`
    8. otherwise, if only `:comment` was given, stop silently
    9. otherwise, warn "No action taken" and report "not updated"

  Ported from `CLI::Issue#update_issue`. Unlike every other function in this
  module, normalizes its result down to `:ok | {:error, reason}` (dropping
  the `{:ok, term}` wrapper) to match `LinearCli.CLI.run/3`'s command-handler
  contract.
  """
  @spec update_issue(%Linear.Issue{}, keyword()) :: :ok | {:error, term()}
  def update_issue(issue, opts \\ []) do
    with :ok <- maybe_comment(issue, opts[:comment], opts) do
      dispatch_update(issue, opts)
    end
  end

  defp maybe_comment(_issue, nil, _opts), do: :ok

  defp maybe_comment(issue, comment, opts) do
    case issue_comment(issue, comment, opts) do
      {:ok, _comment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_update(issue, opts) do
    cond do
      opts[:close] -> normalize(close_issue(issue, opts))
      opts[:cancel] -> normalize(cancel_issue(issue, opts))
      opts[:pr] -> PullRequest.issue_pr(issue, opts)
      opts[:project] -> normalize(attach_project(issue, opts[:project], opts))
      opts[:description] -> normalize(update_description(issue, opts[:description], opts))
      not is_nil(opts[:priority]) -> normalize(set_priority(issue, opts[:priority], opts))
      opts[:comment] -> :ok
      true -> no_action_taken(opts)
    end
  end

  defp no_action_taken(opts) do
    Output.status(:warn, "No action taken, no options specified", opts)
    Output.status(:ok, "Issue was not updated", opts)
    :ok
  end

  defp normalize({:ok, _result}), do: :ok
  defp normalize({:error, reason}), do: {:error, reason}
end
