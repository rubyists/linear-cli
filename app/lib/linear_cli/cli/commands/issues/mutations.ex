defmodule LinearCli.CLI.Commands.Issues.Mutations do
  @moduledoc """
  Issue mutation commands: update, comment, status, and assign.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/update.rb,
  comment.rb, status.rb, and assign.rb.
  """

  alias LinearCli.CLI.{Display, Prompt, WhatFor}
  alias LinearCli.CLI.Issue.{Actions, Identifiers}
  alias LinearCli.Linear

  @max_concurrent_issue_updates 20

  @doc """
  Ported from commands/issue/update.rb: looks up every issue id in `unknown`
  (see `issue_take/2`'s doc for why this is a variadic positional captured
  via `unknown` rather than a declared Optimus arg) and dispatches
  `LinearCli.CLI.Issue.Actions.update_issue/2` against each, per whichever
  flags/options were given.

  Ports `raise SmellsBad, 'No issue IDs provided!' if issue_ids.empty?` as
  `{:error, {:smells_bad, "No issue IDs provided!"}}` (mapped to exit 22 by
  `LinearCli.CLI.handle_error/3`). Ruby's second guard - `raise SmellsBad,
  '...' if options[:pr] && issue_ids.size > 1` - has no equivalent here:
  the real `update.rb` never actually registers a `--pr` option/flag
  (`options[:pr]` can never be truthy there either), so it's dead code in
  the original and isn't ported.
  """
  @spec issue_update(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_update(%{unknown: issue_ids, options: options, flags: flags}) do
    with :ok <- validate_issue_ids(issue_ids),
         :ok <- validate_body_file_exclusion(options, :description, "--description"),
         {:ok, description} <- resolve_body_from_file(options, :description),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &Identifiers.expand_issue_id/1)}) do
      update_opts = [
        comment: options.comment,
        description: description,
        project: options.project,
        cancel: flags.cancel,
        close: flags.close,
        reason: options.reason,
        status: Map.get(options, :status),
        trash: flags.trash
      ]

      Enum.reduce_while(issues, :ok, fn issue, :ok ->
        case Actions.update_issue(issue, update_opts) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  @doc """
  Adds a comment to one or more issues (ISSUE_ID...).

  `--comment`/`-m` and `--body-file` are mutually exclusive. `--body-file`
  reads the body from a file (`-` for stdin) - the way to supply a large
  multi-line body without building it as a single shell argument, which
  is what `--comment`, going through
  `LinearCli.CLI.WhatFor.comment_for/2`'s prompt/editor resolution, does
  not protect against. Without either option, `comment_for/2`'s existing
  behavior applies (prompt, or open an editor for `-`).

  When multiple issue IDs are given, the same comment body is posted to
  each concurrently. The interactive prompt (when neither `-m` nor
  `--body-file` is given) uses the first issue's context.

  Calls `Linear.add_comment/2` directly rather than
  `LinearCli.CLI.Issue.Actions.issue_comment/2` so the confirmation can be
  suppressed under `--output json` - matching how `print_move_results/3`
  suppresses its own confirmation for `issue move --output json`.

  New in this port - Ruby has no equivalent.
  """
  @spec issue_comment(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_comment(%{unknown: issue_ids, options: options}) do
    with :ok <- validate_issue_ids(issue_ids),
         :ok <- validate_body_file_exclusion(options, :comment, "--comment"),
         {:ok, comment_text} <- resolve_body_from_file(options, :comment),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &Identifiers.expand_issue_id/1)}),
         body = WhatFor.comment_for(hd(issues), comment_text),
         {:ok, pairs} <- add_comments_to_issues(issues, body) do
      unless options.output == "json" do
        Enum.each(pairs, fn {issue, _comment} ->
          Prompt.ok("Comment added to #{issue.identifier}")
        end)
      end

      Display.show(one_or_many(Enum.map(pairs, &elem(&1, 1))), %{output: options.output})
      :ok
    end
  end

  @doc """
  Changes the workflow state of one or more issues. Optimus captures the IDs in
  `unknown`, since it has no variadic positional-argument type.

  With `--status`/`-s`, matches the given name against the issue's team's
  workflow states (case-insensitive exact, then unique prefix). Without it,
  prompts interactively via `LinearCli.CLI.Prompt.select/2`.

  With `--comment`/`-m`, adds a comment to each issue before transitioning it.
  Mutations for separate issues run concurrently with a limit of 20 in flight.
  """
  @spec issue_status(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_status(%{unknown: issue_ids, options: options}) do
    with :ok <- validate_issue_ids(issue_ids),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &Identifiers.expand_issue_id/1)}),
         {:ok, planned_updates} <- plan_status_updates(issues, options.status),
         {:ok, completed_updates} <- apply_status_updates(planned_updates, options.comment) do
      show_status_updates(completed_updates, options.output)
    end
  end

  @doc """
  Assigns an issue to a team member.

  With `--assignee`/`-a`, matches the given name against the issue's team's
  members (case-insensitive exact, then unique prefix). Without it, prompts
  interactively via `LinearCli.CLI.Prompt.select/2`.
  """
  @spec issue_assign(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_assign(%{args: %{issue_id: issue_id}, options: options}) do
    expanded_id = Identifiers.expand_issue_id(issue_id)

    with {:ok, [issue]} <- Linear.issues(%{ids: [expanded_id]}),
         {:ok, members} <- Linear.team_members(issue.team.id),
         :ok <- guard_has_members(members, issue),
         {:ok, target_member} <- resolve_target_member(members, options.assignee),
         {:ok, state_id} <- resolve_optional_status(issue, Map.get(options, :status)),
         {:ok, updated} <- Linear.assign_issue(issue, target_member.id, %{state_id: state_id}) do
      Display.show(updated, %{output: options.output})

      if options.output != "json" do
        msg = "#{updated.identifier} assigned to #{target_member.name}"

        msg =
          if updated.state,
            do: "#{msg} and set to #{updated.state.name}",
            else: msg

        Prompt.ok(msg)
      end

      :ok
    end
  end

  defp validate_issue_ids([]), do: {:error, {:smells_bad, "No issue IDs provided!"}}
  defp validate_issue_ids(_issue_ids), do: :ok

  defp validate_body_file_exclusion(options, text_key, flag_name) do
    if not is_nil(Map.get(options, :body_file)) and not is_nil(Map.get(options, text_key)) do
      {:error, {:smells_bad, "give #{flag_name} or --body-file, not both"}}
    else
      :ok
    end
  end

  defp resolve_body_from_file(options, text_key) do
    case Map.get(options, :body_file) do
      nil -> {:ok, Map.get(options, text_key)}
      "-" -> {:ok, read_stdin()}
      path -> File.read(path)
    end
  end

  defp read_stdin do
    case IO.read(:stdio, :eof) do
      :eof -> ""
      data -> data
    end
  end

  defp add_comments_to_issues(issues, body) do
    issues
    |> Task.async_stream(
      fn issue ->
        case Linear.add_comment(issue.identifier, body) do
          {:ok, comment} -> {:ok, {issue, comment}}
          {:error, reason} -> {:error, reason}
        end
      end,
      max_concurrency: min(length(issues), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, pair}}, {:ok, acc} -> {:cont, {:ok, [pair | acc]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end)
  end

  defp one_or_many([one]), do: one
  defp one_or_many(many), do: many

  defp plan_status_updates(issues, status) do
    issues
    |> Enum.reduce_while({:ok, []}, fn issue, {:ok, updates} ->
      with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id),
           {:ok, target_state} <- resolve_target_state(states, status) do
        {:cont, {:ok, [{issue, target_state} | updates]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_status_updates()
  end

  defp apply_status_updates([], _comment), do: {:ok, []}

  defp apply_status_updates(planned_updates, comment) do
    planned_updates
    |> Task.async_stream(
      fn {issue, target_state} ->
        apply_status_update(issue, target_state, comment)
      end,
      max_concurrency: min(length(planned_updates), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, update}}, {:ok, updates} ->
        {:cont, {:ok, [update | updates]}}

      {:ok, {:error, reason}}, {:ok, _updates} ->
        {:halt, {:error, reason}}

      {:exit, reason}, {:ok, _updates} ->
        {:halt, {:error, {:task_exit, reason}}}
    end)
    |> reverse_status_updates()
  end

  defp apply_status_update(issue, target_state, comment) do
    with :ok <- maybe_add_status_comment(issue, comment),
         {:ok, updated} <- Linear.set_issue_status(issue, target_state.id) do
      {:ok, {updated, target_state}}
    end
  end

  defp reverse_status_updates({:ok, updates}), do: {:ok, Enum.reverse(updates)}
  defp reverse_status_updates(error), do: error

  defp show_status_updates(completed_updates, output) do
    updated_issues = Enum.map(completed_updates, &elem(&1, 0))
    Display.show(one_or_many(updated_issues), %{output: output})

    if output != "json" do
      Enum.each(completed_updates, fn {updated, target_state} ->
        Prompt.ok("#{updated.identifier} status set to #{target_state.name}")
      end)
    end

    :ok
  end

  defp resolve_target_state(states, nil) do
    choices = Enum.sort_by(states, & &1.position) |> Enum.map(&{&1.name, &1})
    {:ok, Prompt.select("Choose a status", choices)}
  end

  defp resolve_target_state(states, name) do
    normalized_name = String.downcase(name)

    states
    |> Enum.filter(&(String.downcase(&1.name) == normalized_name))
    |> use_prefix_matches_if_empty(states, normalized_name)
    |> resolve_state_matches(states, name)
  end

  defp use_prefix_matches_if_empty([], states, name) do
    Enum.filter(states, &String.starts_with?(String.downcase(&1.name), name))
  end

  defp use_prefix_matches_if_empty(matches, _states, _name), do: matches

  defp resolve_state_matches([state], _states, _name), do: {:ok, state}

  defp resolve_state_matches([], states, name) do
    available = Enum.map_join(states, ", ", & &1.name)
    {:error, {:smells_bad, "Unknown status #{inspect(name)}. Available: #{available}"}}
  end

  defp resolve_state_matches(matches, _states, name) do
    ambiguous = Enum.map_join(matches, ", ", & &1.name)
    {:error, {:smells_bad, "Ambiguous status #{inspect(name)}: matches #{ambiguous}"}}
  end

  defp maybe_add_status_comment(_issue, nil), do: :ok

  defp maybe_add_status_comment(issue, comment) do
    case Actions.issue_comment(issue, comment) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_optional_status(_issue, nil), do: {:ok, nil}

  defp resolve_optional_status(issue, name) do
    with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id),
         {:ok, state} <- resolve_target_state(states, name) do
      {:ok, state.id}
    end
  end

  defp guard_has_members([], issue) do
    {:error,
     {:smells_bad, "No assignable members found for team #{issue.team.key || issue.team.id}"}}
  end

  defp guard_has_members(_members, _issue), do: :ok

  defp resolve_target_member(members, nil) do
    choices = Enum.sort_by(members, & &1.name) |> Enum.map(&{&1.name, &1})
    {:ok, Prompt.select("Choose an assignee", choices)}
  end

  defp resolve_target_member(members, name) do
    normalized = String.downcase(name)

    members
    |> Enum.filter(&(String.downcase(&1.name) == normalized))
    |> use_prefix_member_matches_if_empty(members, normalized)
    |> resolve_member_matches(members, name)
  end

  defp use_prefix_member_matches_if_empty([], members, name) do
    Enum.filter(members, &String.starts_with?(String.downcase(&1.name), name))
  end

  defp use_prefix_member_matches_if_empty(matches, _members, _name), do: matches

  defp resolve_member_matches([member], _members, _name), do: {:ok, member}

  defp resolve_member_matches([], members, name) do
    available = Enum.map_join(Enum.sort_by(members, & &1.name), ", ", & &1.name)
    {:error, {:smells_bad, "Unknown assignee #{inspect(name)}. Available: #{available}"}}
  end

  defp resolve_member_matches(matches, _members, name) do
    ambiguous = Enum.map_join(matches, ", ", & &1.name)
    {:error, {:smells_bad, "Ambiguous assignee #{inspect(name)}: matches #{ambiguous}"}}
  end
end
