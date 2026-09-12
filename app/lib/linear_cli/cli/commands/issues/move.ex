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

  # UUID by structure: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (8-4-4-4-12, dashes at fixed positions)
  defp resolve_bulk_project(
         <<_::8*8, ?-, _::4*8, ?-, _::4*8, ?-, _::4*8, ?-, _::12*8>> = uuid,
         _team_fn
       ) do
    short_name = String.slice(uuid, 0, 8) <> "…"
    {:ok, struct(LinearCli.Linear.Project, %{id: uuid, name: short_name})}
  end

  defp resolve_bulk_project(value, team_fn) do
    team = team_fn.()

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: value}),
         project when not is_nil(project) <- Projects.project_for(projects, value) do
      {:ok, project}
    else
      nil -> {:error, {:smells_bad, "No project found matching #{value}"}}
      {:error, reason} -> {:error, reason}
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
