defmodule LinearCli.CLI.Commands.Issues.Move do
  @moduledoc """
  Issue move command: moves issues to a target project by ID or in bulk.
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
         {:ok, expanded_ids} <- Identifiers.expand_issue_ids(issue_ids, output: options.output),
         {:ok, issues} <-
           Linear.issues(%{ids: expanded_ids}),
         {:ok, project} <- resolve_move_project(issues, options) do
      print_move_plan(issues, project, options.output)
      execute_moves_if_confirmed(issues, project, flags, options.output)
    end
  end

  defp resolve_move_project(_issues, %{project: nil, output: "json"}) do
    {:error, {:smells_bad, "JSON output requires --project for issue move"}}
  end

  defp resolve_move_project(issues, options) do
    with {:ok, tid} <- resolve_move_team_id(options.team || Profiles.default_team(), issues),
         {:ok, projects} <- Linear.projects_by_team(tid, %{search: options.project}) do
      project =
        if options.output == "json" do
          Projects.project_for_strict(projects, options.project)
        else
          Projects.project_for(projects, options.project)
        end

      project_result(project, projects, options.project, options.output)
    end
  end

  defp project_result(nil, projects, search, "json") do
    if Projects.project_scores(projects, search) == [] do
      {:error, {:smells_bad, "No project found matching #{search}"}}
    else
      {:error,
       {:smells_bad, "JSON output requires an exact project match for #{inspect(search)}"}}
    end
  end

  defp project_result(nil, _projects, search, _output),
    do: {:error, {:smells_bad, "No project found matching #{inspect(search)}"}}

  defp project_result(project, _projects, _search, _output), do: {:ok, project}

  defp resolve_move_team_id(nil, issues), do: {:ok, hd(issues).team.id}

  defp resolve_move_team_id(key, _issues) do
    with {:ok, team} <- Linear.find_team(key), do: {:ok, team.id}
  end

  defp execute_moves_if_confirmed(issues, _project, %{dry_run: true}, "json") do
    Display.show(one_or_many(issues), %{output: "json"})
    :ok
  end

  defp execute_moves_if_confirmed(_issues, _project, %{dry_run: true}, _output), do: :ok

  defp execute_moves_if_confirmed(issues, project, %{yes: true}, output),
    do: apply_moves(issues, project, output)

  defp execute_moves_if_confirmed(_issues, _project, _flags, "json") do
    {:error, {:smells_bad, "JSON output requires --yes or --dry-run for issue move"}}
  end

  defp execute_moves_if_confirmed(issues, project, _flags, output) do
    if Prompt.confirm_destructive?("Proceed with move?"),
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

  defp move_issues_by_project(options, flags) do
    team_key = options.team || Profiles.default_team()
    team_fn = fn -> WhatFor.team_for(team_key) end

    with :ok <- validate_bulk_team(team_key, options),
         {:ok, source} <- resolve_bulk_project(options.from, team_fn, options.output),
         {:ok, target} <- resolve_bulk_project(options.to, team_fn, options.output),
         :ok <- guard_different_projects(source, target),
         {:ok, issues} <- Linear.issues(%{project_id: source.id, mine: false, all: flags.all}) do
      handle_bulk_move(issues, source, target, flags, options)
    end
  end

  defp handle_bulk_move([], _source, _target, _flags, %{output: "json"}) do
    Display.show([], %{output: "json"})
    :ok
  end

  defp handle_bulk_move([], source, _target, flags, %{output: _output}) do
    label = if flags.all, do: "issues", else: "open issues"
    Prompt.ok("No #{label} in #{source.name} to move")
    :ok
  end

  defp handle_bulk_move(issues, source, target, %{dry_run: true}, options) do
    Display.show(one_or_many(issues), %{output: options.output})
    print_bulk_dry_run(issues, source, target, options)
    :ok
  end

  defp handle_bulk_move(_issues, _source, _target, %{yes: false}, %{output: "json"}) do
    {:error, {:smells_bad, "JSON output requires --yes or --dry-run for issue move"}}
  end

  defp handle_bulk_move(issues, source, target, %{yes: false}, options) do
    if Prompt.confirm_destructive?(
         "Move #{length(issues)} issue(s) from #{source.name} to #{target.name}?"
       ),
       do: apply_project_moves_and_show(issues, source, target, options.output),
       else: Prompt.warn("Move cancelled")
  end

  defp handle_bulk_move(issues, source, target, %{yes: true}, options),
    do: apply_project_moves_and_show(issues, source, target, options.output)

  defp print_bulk_dry_run(_issues, _source, _target, %{output: "json"}), do: :ok

  defp print_bulk_dry_run(issues, source, target, %{output: output}) when output != "json" do
    Prompt.ok("Would move #{length(issues)} issue(s) from #{source.name} to #{target.name}")
  end

  defp apply_project_moves_and_show(issues, source, target, output) do
    with {:ok, pairs} <- apply_project_moves(issues, target) do
      show_move_results(pairs, source, target, output)
    end
  end

  # UUID by structure: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (8-4-4-4-12, dashes at fixed positions)
  defp resolve_bulk_project(
         <<_::8*8, ?-, _::4*8, ?-, _::4*8, ?-, _::4*8, ?-, _::12*8>> = uuid,
         _team_fn,
         _output
       ) do
    short_name = String.slice(uuid, 0, 8) <> "…"
    {:ok, struct(LinearCli.Linear.Project, %{id: uuid, name: short_name})}
  end

  defp resolve_bulk_project(value, team_fn, output) do
    team = team_fn.()

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: value}) do
      case project_for_bulk(projects, value, output) do
        nil -> bulk_project_error(projects, value, output)
        project -> {:ok, project}
      end
    end
  end

  defp bulk_project_error(projects, value, "json") do
    if Projects.project_scores(projects, value) == [] do
      {:error, {:smells_bad, "No project found matching #{value}"}}
    else
      {:error, {:smells_bad, "JSON output requires an exact project match for #{inspect(value)}"}}
    end
  end

  defp bulk_project_error(_projects, value, _output),
    do: {:error, {:smells_bad, "No project found matching #{value}"}}

  defp project_for_bulk(projects, value, "json"),
    do: Projects.project_for_strict(projects, value)

  defp project_for_bulk(projects, value, _output),
    do: Projects.project_for(projects, value)

  defp validate_bulk_team(nil, %{output: "json", from: from, to: to}) do
    if uuid?(from) and uuid?(to) do
      :ok
    else
      {:error,
       {:smells_bad, "JSON output requires --team or an active profile for bulk issue move"}}
    end
  end

  defp validate_bulk_team(_team_key, _options), do: :ok

  defp uuid?(<<_::8*8, ?-, _::4*8, ?-, _::4*8, ?-, _::4*8, ?-, _::12*8>>),
    do: true

  defp uuid?(_value), do: false

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

  defp show_move_results(pairs, _source, _target, "json") do
    Display.show(one_or_many(Enum.map(pairs, &elem(&1, 1))), %{output: "json"})
    :ok
  end

  defp show_move_results(pairs, source, target, _output) do
    Enum.each(pairs, fn {orig, _updated} ->
      Prompt.ok("#{orig.identifier} moved to #{target.name}")
    end)

    Prompt.ok("Moved #{length(pairs)} issue(s) from #{source.name} to #{target.name}")
    :ok
  end

  defp one_or_many([one]), do: one
  defp one_or_many(many), do: many
end
