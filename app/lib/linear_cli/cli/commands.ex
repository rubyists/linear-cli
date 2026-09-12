defmodule LinearCli.CLI.Commands do
  @moduledoc """
  Remaining issue command implementations pending extraction in EXT-54: move
  and relation commands. Fetch via `LinearCli.Linear`, display the result.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/**.

  All other command families live in their own focused modules:
  `LinearCli.CLI.Commands.System`, `LinearCli.CLI.Commands.Teams`,
  `LinearCli.CLI.Commands.Projects`, `LinearCli.CLI.Commands.Profiles`,
  `LinearCli.CLI.Commands.Issues.Read`, `LinearCli.CLI.Commands.Issues.Create`,
  `LinearCli.CLI.Commands.Issues.Development`, and
  `LinearCli.CLI.Commands.Issues.Mutations`.
  """

  alias LinearCli.CLI.{Display, Projects, Prompt, WhatFor}
  alias LinearCli.CLI.Issue.Identifiers
  alias LinearCli.{Linear, Profiles}

  @max_concurrent_issue_updates 20

  @doc """
  Moves issues to a target project.

  Two modes:
  - **ID-based** (EXT-9): `ISSUE_ID... --project P [--team T]` — moves the
    listed issues to the named project, resolved per-issue from the issue's
    own team or the given `--team`. Concurrent apply, same pattern as
    `issue_status/1`.
  - **Bulk project-to-project** (Phase 12): `--from P --to P [--team T]` —
    lists all open issues (or all with `--all`) from the source project and
    fans out mutations to the target project concurrently.

  With `--dry-run`, prints the planned moves without mutating.
  Without `--yes`, asks for confirmation before applying.
  """
  @spec issue_move(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_move(%{unknown: issue_ids, options: options, flags: flags}) do
    cond do
      options.from && options.to ->
        move_issues_by_project(options, flags)

      options.from || options.to ->
        {:error,
         {:smells_bad, "--from and --to must both be given for bulk project-to-project mode"}}

      true ->
        move_issues_by_id(issue_ids, options, flags)
    end
  end

  defp move_issues_by_id(issue_ids, options, flags) do
    with :ok <- validate_issue_ids(issue_ids),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &Identifiers.expand_issue_id/1)}),
         {:ok, project} <- resolve_move_project(issues, options) do
      print_move_plan(issues, project, options.output)
      execute_moves_if_confirmed(issues, project, flags, options.output)
    end
  end

  defp resolve_move_project(issues, options) do
    with {:ok, tid} <- resolve_move_team_id(options.team || Profiles.default_team(), issues),
         {:ok, projects} <- Linear.projects_by_team(tid, %{search: options.project}) do
      project_result(Projects.project_for(projects, options.project), options.project)
    end
  end

  defp project_result(nil, search),
    do: {:error, {:smells_bad, "No project found matching #{inspect(search)}"}}

  defp project_result(project, _search), do: {:ok, project}

  defp resolve_move_team_id(nil, issues), do: {:ok, hd(issues).team.id}

  defp resolve_move_team_id(key, _issues) do
    with {:ok, team} <- Linear.find_team(key), do: {:ok, team.id}
  end

  defp execute_moves_if_confirmed(_issues, _project, %{dry_run: true}, _output), do: :ok

  defp execute_moves_if_confirmed(issues, project, %{yes: true}, output),
    do: apply_moves(issues, project, output)

  defp execute_moves_if_confirmed(issues, project, _flags, output) do
    if Prompt.yes?("Proceed with move?"),
      do: apply_moves(issues, project, output),
      else: Prompt.warn("Move cancelled")
  end

  defp print_move_plan(issues, project, output) when output != "json" do
    Enum.each(issues, fn issue ->
      Prompt.say("#{issue.identifier} -> #{project.name}")
    end)
  end

  defp print_move_plan(_issues, _project, _output), do: :ok

  defp apply_moves(issues, project, output) do
    issues
    |> Task.async_stream(
      fn issue -> apply_move(issue, project) end,
      max_concurrency: min(length(issues), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, updated}}, {:ok, acc} -> {:cont, {:ok, [updated | acc]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> display_moves_result(project, output)
  end

  defp display_moves_result({:ok, updated_issues}, project, output) do
    updated_issues = Enum.reverse(updated_issues)
    Display.show(one_or_many(updated_issues), %{output: output})
    print_move_results(updated_issues, project, output)
    :ok
  end

  defp display_moves_result(error, _project, _output), do: error

  defp print_move_results(updated_issues, project, output) when output != "json" do
    Enum.each(updated_issues, fn updated ->
      Prompt.ok("#{updated.identifier} moved to #{project.name}")
    end)
  end

  defp print_move_results(_updated_issues, _project, _output), do: :ok

  defp apply_move(issue, project) do
    Linear.attach_issue_to_project(issue, project.id)
  end

  defp validate_issue_ids([]), do: {:error, {:smells_bad, "No issue IDs provided!"}}
  defp validate_issue_ids(_issue_ids), do: :ok

  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  defp move_issues_by_project(options, flags) do
    team_fn = fn -> WhatFor.team_for(options.team || Profiles.default_team()) end

    with {:ok, source} <- resolve_bulk_project(options.from, team_fn),
         {:ok, target} <- resolve_bulk_project(options.to, team_fn),
         :ok <- guard_different_projects(source, target),
         {:ok, issues} <- Linear.issues(%{project_id: source.id, mine: false, all: flags.all}) do
      cond do
        issues == [] ->
          label = if flags.all, do: "issues", else: "open issues"
          Prompt.ok("No #{label} in #{source.name} to move")
          :ok

        flags.dry_run ->
          Display.show(one_or_many(issues), %{output: options.output})
          Prompt.ok("Would move #{length(issues)} issue(s) from #{source.name} to #{target.name}")
          :ok

        not flags.yes and
            not Prompt.yes?(
              "Move #{length(issues)} issue(s) from #{source.name} to #{target.name}?"
            ) ->
          Prompt.warn("Move cancelled")

        true ->
          with {:ok, pairs} <- apply_project_moves(issues, target) do
            show_move_results(pairs, source, target, options.output)
          end
      end
    end
  end

  defp resolve_bulk_project(value, team_fn) do
    if Regex.match?(@uuid_regex, value) do
      short_name = String.slice(value, 0, 8) <> "…"
      {:ok, struct(LinearCli.Linear.Project, %{id: value, name: short_name})}
    else
      team = team_fn.()

      with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: value}),
           project when not is_nil(project) <- Projects.project_for(projects, value) do
        {:ok, project}
      else
        nil -> {:error, {:smells_bad, "No project found matching #{value}"}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp guard_different_projects(%{id: id}, %{id: id}),
    do: {:error, {:smells_bad, "source and target are the same project"}}

  defp guard_different_projects(_source, _target), do: :ok

  defp apply_project_moves(issues, target) do
    issues
    |> Task.async_stream(
      fn issue ->
        case Linear.attach_issue_to_project(issue, target.id) do
          {:ok, updated} -> {:ok, {issue, updated}}
          {:error, reason} -> {:error, reason}
        end
      end,
      max_concurrency: min(length(issues), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, pair}}, {:ok, acc} -> {:cont, {:ok, [pair | acc]}}
      {:ok, {:error, reason}}, {:ok, _acc} -> {:halt, {:error, reason}}
      {:exit, reason}, {:ok, _acc} -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end)
  end

  defp show_move_results(pairs, source, target, output) do
    if output == "json" do
      Display.show(one_or_many(Enum.map(pairs, &elem(&1, 1))), %{output: "json"})
    else
      Enum.each(pairs, fn {orig, _updated} ->
        Prompt.ok("#{orig.identifier} moved to #{target.name}")
      end)

      Prompt.ok("Moved #{length(pairs)} issue(s) from #{source.name} to #{target.name}")
    end

    :ok
  end

  defp one_or_many([one]), do: one
  defp one_or_many(many), do: many

  @doc """
  Lists the relationships for a single issue — both outbound (issues this one
  blocks/is-related-to/is-duplicate-of) and inbound (issues that block this
  one, etc.).

  Calls `Linear.issue_relations/1` which fetches both `relations` and
  `inverseRelations` from Linear and tags each with a direction.
  """
  @spec issue_relation_list(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_relation_list(%{args: %{issue_id: issue_id}, options: options}) do
    expanded_id = Identifiers.expand_issue_id(issue_id)

    with {:ok, relations} <- Linear.issue_relations(expanded_id) do
      Display.show(relations, %{output: options.output, relations: true})
      :ok
    end
  end

  @doc """
  Adds a relationship from `ISSUE` to one or more `RELATED_ISSUE`s.

  The first element of `unknown` is the subject issue; the remaining
  elements are the related issues.  `--type` controls direction:

  * `blocks`     — subject blocks each related issue (wire: `blocks`, subject → related)
  * `blocked-by` — subject is blocked by each related issue (wire: `blocks`, reversed: related → subject)
  * `related`    — subject is related to each related issue
  * `duplicate`  — subject is a duplicate of each related issue

  Each target is processed independently; partial failures do not roll back
  successful mutations.  All results are printed before returning; a non-zero
  exit identifies the overall failure count if any target failed.
  """
  @spec issue_relation_add(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_relation_add(%{unknown: []}),
    do: {:error, {:smells_bad, "ISSUE and at least one RELATED_ISSUE are required"}}

  def issue_relation_add(%{unknown: [_subject]}),
    do: {:error, {:smells_bad, "At least one RELATED_ISSUE is required"}}

  def issue_relation_add(%{unknown: [subject_id | related_ids], options: options}) do
    expanded_subject = Identifiers.expand_issue_id(subject_id)
    user_type = options.type

    results =
      Enum.map(related_ids, fn related_id ->
        expanded_related = Identifiers.expand_issue_id(related_id)
        add_single_relation(expanded_subject, expanded_related, user_type)
      end)

    print_relation_add_results(results, options.output)

    failed_count =
      Enum.count(results, fn r -> match?({:failed, _, _}, r) or match?({:self_link, _}, r) end)

    if failed_count > 0 do
      {:error, {:smells_bad, "#{failed_count} relation(s) failed to be created"}}
    else
      :ok
    end
  end

  defp add_single_relation(subject_id, related_id, _user_type) when subject_id == related_id do
    {:self_link, subject_id}
  end

  defp add_single_relation(subject_id, related_id, user_type) do
    {wire_issue_id, wire_related_id, wire_type, direction} =
      if user_type == "blocked-by" do
        {related_id, subject_id, "blocks", :inbound}
      else
        {subject_id, related_id, user_type, :outbound}
      end

    case Linear.create_issue_relation(wire_issue_id, wire_related_id, wire_type) do
      {:ok, relation} ->
        {:created, related_id, %{relation | direction: direction}}

      {:error, %Ash.Error.Unknown{errors: [%{value: [{:duplicate_relation, _}]} | _]}} ->
        {:exists, related_id}

      {:error, reason} ->
        {:failed, related_id, reason}
    end
  end

  defp print_relation_add_results(results, output) do
    if output == "json" do
      results
      |> Enum.map(&relation_add_result_to_plain/1)
      |> Jason.encode!(pretty: true)
      |> IO.puts()
    else
      Enum.each(results, &print_relation_add_result_text/1)
    end
  end

  defp relation_add_result_to_plain({:created, related_id, relation}) do
    %{
      "target" => related_id,
      "status" => "created",
      "relation" => Display.relation_to_plain(relation)
    }
  end

  defp relation_add_result_to_plain({:exists, related_id}) do
    %{"target" => related_id, "status" => "exists"}
  end

  defp relation_add_result_to_plain({:self_link, id}) do
    %{
      "target" => id,
      "status" => "error",
      "message" => "self-link: an issue cannot be related to itself"
    }
  end

  defp relation_add_result_to_plain({:failed, related_id, reason}) do
    msg = reason |> relation_add_error_message() |> truncate_message(200)
    %{"target" => related_id, "status" => "error", "message" => msg}
  end

  defp print_relation_add_result_text({:created, _related_id, relation}) do
    IO.puts(relation_add_created_text(relation))
  end

  defp print_relation_add_result_text({:exists, related_id}) do
    Prompt.ok("#{related_id}: relation already exists (no change)")
  end

  defp print_relation_add_result_text({:self_link, id}) do
    IO.puts(:stderr, "#{id}: self-link — an issue cannot be related to itself")
  end

  defp print_relation_add_result_text({:failed, related_id, reason}) do
    msg = relation_add_error_message(reason)
    IO.puts(:stderr, "#{related_id}: #{msg}")
  end

  defp relation_add_created_text(%{type: "blocks", issue: issue, related_issue: related}) do
    "#{issue.identifier} now blocks #{related.identifier}"
  end

  defp relation_add_created_text(%{type: "related", issue: issue, related_issue: related}) do
    "#{issue.identifier} is now related to #{related.identifier}"
  end

  defp relation_add_created_text(%{type: "duplicate", issue: issue, related_issue: related}) do
    "#{issue.identifier} is now a duplicate of #{related.identifier}"
  end

  defp relation_add_created_text(%{type: type, issue: issue, related_issue: related}) do
    "#{issue.identifier} is now a #{type} of #{related.identifier}"
  end

  defp relation_add_error_message(%Ash.Error.Unknown{
         errors: [%{value: [{:graphql_errors, [%{"message" => msg} | _]}]} | _]
       }),
       do: "Linear API error: #{msg}"

  defp relation_add_error_message(%Ash.Error.Unknown{
         errors: [%Ash.Error.Unknown.UnknownError{error: "unknown error: :missing_api_key"} | _]
       }),
       do: "LINEAR_API_KEY is not set"

  defp relation_add_error_message(_reason), do: "unexpected error"

  defp truncate_message(msg, max) when byte_size(msg) > max,
    do: String.slice(msg, 0, max) <> "…"

  defp truncate_message(msg, _max), do: msg

  @doc """
  Removes a relationship from `ISSUE` to one or more `RELATED_ISSUE`s.

  The first element of `unknown` is the subject issue; the remaining elements
  are the related issues.  `--type` controls which stored relation to match:

  * `blocks`     — removes the relation where subject blocks each related issue
  * `blocked-by` — removes the relation where each related issue blocks subject
  * `related`    — removes the related relation
  * `duplicate`  — removes the duplicate relation

  Removing an absent relation is a per-target no-op (not an error).  If more
  than one stored relation matches for a target, that target fails and every
  matching relation ID is listed — nothing is deleted arbitrarily.

  Each target is processed independently; partial failures do not roll back
  successful deletions.  All results are printed before returning; a non-zero
  exit identifies the overall failure count if any target failed.
  """
  @spec issue_relation_remove(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_relation_remove(%{unknown: []}),
    do: {:error, {:smells_bad, "ISSUE and at least one RELATED_ISSUE are required"}}

  def issue_relation_remove(%{unknown: [_subject]}),
    do: {:error, {:smells_bad, "At least one RELATED_ISSUE is required"}}

  def issue_relation_remove(%{unknown: [subject_id | related_ids], options: options}) do
    expanded_subject = Identifiers.expand_issue_id(subject_id)
    user_type = options.type

    with {:ok, all_relations} <- Linear.issue_relations(expanded_subject) do
      results =
        Enum.map(related_ids, fn related_id ->
          expanded_related = Identifiers.expand_issue_id(related_id)
          remove_single_relation(expanded_subject, expanded_related, user_type, all_relations)
        end)

      print_relation_remove_results(results, options.output)

      failed_count =
        Enum.count(results, fn r ->
          match?({:failed, _, _}, r) or match?({:ambiguous, _, _}, r) or
            match?({:self_link, _}, r)
        end)

      if failed_count > 0 do
        {:error, {:smells_bad, "#{failed_count} relation(s) failed to be removed"}}
      else
        :ok
      end
    end
  end

  defp remove_single_relation(subject_id, related_id, _user_type, _relations)
       when subject_id == related_id do
    {:self_link, subject_id}
  end

  defp remove_single_relation(subject_id, related_id, user_type, all_relations) do
    subject_id
    |> find_matching_relations(related_id, user_type, all_relations)
    |> do_remove(related_id)
  end

  defp do_remove([], related_id), do: {:absent, related_id}

  defp do_remove([relation], related_id) do
    case Linear.delete_issue_relation(relation) do
      :ok -> {:removed, related_id, relation}
      {:error, reason} -> {:failed, related_id, reason}
    end
  end

  defp do_remove(relations, related_id) do
    {:ambiguous, related_id, Enum.map(relations, & &1.id)}
  end

  # Finds stored relations that match the user-facing type and the given endpoint pair.
  # For `blocked-by`: the stored relation is `blocks` in the inbound direction, meaning
  # the related_id issue is the source (`issue`) and subject is the destination (`related_issue`).
  # For all other types: the stored relation is outbound with the subject as source.
  defp find_matching_relations(_subject_id, related_id, "blocked-by", all_relations) do
    Enum.filter(all_relations, fn rel ->
      rel.direction == :inbound and
        rel.type == "blocks" and
        rel.issue != nil and
        rel.issue.identifier == related_id
    end)
  end

  defp find_matching_relations(_subject_id, related_id, user_type, all_relations) do
    Enum.filter(all_relations, fn rel ->
      rel.direction == :outbound and
        rel.type == user_type and
        rel.related_issue != nil and
        rel.related_issue.identifier == related_id
    end)
  end

  defp print_relation_remove_results(results, output) do
    if output == "json" do
      results
      |> Enum.map(&relation_remove_result_to_plain/1)
      |> Jason.encode!(pretty: true)
      |> IO.puts()
    else
      Enum.each(results, &print_relation_remove_result_text/1)
    end
  end

  defp relation_remove_result_to_plain({:removed, related_id, relation}) do
    %{
      "target" => related_id,
      "status" => "removed",
      "relation" => Display.relation_to_plain(relation)
    }
  end

  defp relation_remove_result_to_plain({:absent, related_id}) do
    %{"target" => related_id, "status" => "absent"}
  end

  defp relation_remove_result_to_plain({:self_link, id}) do
    %{
      "target" => id,
      "status" => "error",
      "message" => "self-link: an issue cannot be related to itself"
    }
  end

  defp relation_remove_result_to_plain({:ambiguous, related_id, ids}) do
    %{
      "target" => related_id,
      "status" => "error",
      "message" => "ambiguous: multiple matching relations found: #{Enum.join(ids, ", ")}"
    }
  end

  defp relation_remove_result_to_plain({:failed, related_id, reason}) do
    msg = reason |> relation_remove_error_message() |> truncate_message(200)
    %{"target" => related_id, "status" => "error", "message" => msg}
  end

  defp print_relation_remove_result_text({:removed, _related_id, relation}) do
    IO.puts(relation_remove_removed_text(relation))
  end

  defp print_relation_remove_result_text({:absent, related_id}) do
    Prompt.ok("#{related_id}: relation not found (no change)")
  end

  defp print_relation_remove_result_text({:self_link, id}) do
    IO.puts(:stderr, "#{id}: self-link — an issue cannot be related to itself")
  end

  defp print_relation_remove_result_text({:ambiguous, related_id, ids}) do
    IO.puts(
      :stderr,
      "#{related_id}: ambiguous — #{length(ids)} matching relations: #{Enum.join(ids, ", ")}"
    )
  end

  defp print_relation_remove_result_text({:failed, related_id, reason}) do
    msg = relation_remove_error_message(reason)
    IO.puts(:stderr, "#{related_id}: #{msg}")
  end

  defp relation_remove_removed_text(%{type: "blocks", issue: issue, related_issue: related}) do
    "#{issue.identifier} no longer blocks #{related.identifier}"
  end

  defp relation_remove_removed_text(%{type: "related", issue: issue, related_issue: related}) do
    "#{issue.identifier} is no longer related to #{related.identifier}"
  end

  defp relation_remove_removed_text(%{type: "duplicate", issue: issue, related_issue: related}) do
    "#{issue.identifier} is no longer a duplicate of #{related.identifier}"
  end

  defp relation_remove_removed_text(%{type: type, issue: issue, related_issue: related}) do
    "#{issue.identifier} is no longer a #{type} of #{related.identifier}"
  end

  defp relation_remove_error_message(%Ash.Error.Unknown{
         errors: [%{value: [{:graphql_errors, [%{"message" => msg} | _]}]} | _]
       }),
       do: "Linear API error: #{msg}"

  defp relation_remove_error_message(%Ash.Error.Unknown{
         errors: [%Ash.Error.Unknown.UnknownError{error: "unknown error: :missing_api_key"} | _]
       }),
       do: "LINEAR_API_KEY is not set"

  defp relation_remove_error_message(_reason), do: "unexpected error"
end
