defmodule LinearCli.CLI.Commands.Projects do
  @moduledoc """
  Project commands: list, favorite, unfavorite, and update.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/project/.
  """

  alias LinearCli.CLI.{Display, Output, Projects, Prompt, WhatFor}
  alias LinearCli.{Favorites, Linear, Profiles}
  alias LinearCli.Linear.Project

  @doc "Ported from commands/project/list.rb. Ruby's `--mine` defaults false."
  def project_list(%{flags: flags, options: options}) do
    with {:ok, cached} <- Favorites.records("project", flags.all) do
      if cached == nil and paged?(flags, options) do
        show_pages(flags, options, nil)
      else
        with {:ok, projects} <- listed_projects(cached, flags, options),
             {:ok, projects} <- refresh_updates(cached, projects, flags) do
          show_projects(projects, flags, options)
        end
      end
    end
  end

  # Interactive, workspace-wide, unfiltered listings (the caller has already
  # ruled out a favorites filter) are shown 100 at a time, asking before each
  # further page. Everything else (JSON, pipes, --mine, --team) fetches every
  # page.
  defp paged?(flags, options) do
    interactive?() and not Output.json?(options) and not flags.mine and
      not is_binary(options.team)
  end

  defp interactive? do
    case Application.get_env(:linear_cli, :interactive) do
      nil -> :prim_tty.isatty(:stdin) == true and :prim_tty.isatty(:stdout) == true
      interactive? when is_boolean(interactive?) -> interactive?
    end
  end

  defp show_pages(flags, options, cursor) do
    with {:ok, %{projects: projects, has_next_page: more?, end_cursor: next}} <-
           Linear.projects_page(%{after: cursor, with_updates: flags.updates}) do
      show_projects(projects, flags, options)

      if more? and Prompt.yes?("Show the next 100 projects?") do
        show_pages(flags, options, next)
      else
        :ok
      end
    end
  end

  defp show_projects(projects, flags, options) do
    Display.show(projects, %{output: options.output, updates: flags.updates})
    :ok
  end

  # Favorites are served from cached snapshots, which carry no project
  # updates. When `--updates` is given, refetch each favorite with its latest
  # update. Listings fetched live already include them.
  defp refresh_updates(nil, projects, _flags), do: {:ok, projects}
  defp refresh_updates(_cached, projects, %{updates: false}), do: {:ok, projects}

  defp refresh_updates(_cached, projects, _flags) do
    projects
    |> Task.async_stream(&Linear.find_project(&1.id, %{with_updates: true}),
      max_concurrency: 4,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, refreshed}}, {:ok, acc} -> {:cont, {:ok, [refreshed | acc]}}
      {:ok, {:error, reason}}, {:ok, _acc} -> {:halt, {:error, reason}}
      {:exit, reason}, {:ok, _acc} -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> case do
      {:ok, refreshed} -> {:ok, Enum.reverse(refreshed)}
      error -> error
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Favorites a project
  (`LinearCli.Favorites`), resolved against the active team's projects,
  prompting if ambiguous. Team is resolved via `--team`, the active
  profile, or an interactive prompt. Once any project is favorited,
  `project list` defaults to showing just favorites (`--all` overrides).
  `--updates` also shows each project's most recent status update. An
  interactive, unscoped listing is paged 100 projects at a time, asking before
  each next page; every other listing fetches all projects.
  """
  def project_favorite(%{args: %{project: search}, options: options}) do
    with {:ok, team} <- resolve_team(options),
         {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         {:ok, project} <- resolve_project(projects, search, options),
         {:ok, project} <- Linear.find_project(project.id) do
      :ok = Favorites.save("project", project)

      if Output.json?(options) do
        Output.success("project_favorite", %{"project" => project.id}, options)
      else
        Prompt.ok("Favorited project #{project.name}")
      end

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Un-favorites a project."
  def project_unfavorite(%{args: %{project: search}, options: options}) do
    with {:ok, team} <- resolve_team(options),
         {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         {:ok, project} <- resolve_project(projects, search, options) do
      Favorites.remove("project", project.id)

      if Output.json?(options) do
        Output.success("project_unfavorite", %{"project" => project.id}, options)
      else
        Prompt.ok("Un-favorited project #{project.name}")
      end

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Posts a status update to a Linear project. The search covers the whole
  workspace unless `--team` limits it. If multiple projects match exactly,
  text mode prompts for a choice and JSON mode returns an error.
  """
  def project_update(%{args: %{project: search}, options: options}) do
    with {:ok, projects} <- update_candidates(options, search),
         {:ok, project} <- resolve_update_project(projects, search, options),
         {:ok, update} <-
           Linear.post_project_update(project.id, options.body, %{health: options.health}) do
      Display.show(update, %{output: options.output})
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_candidates(%{team: team_key} = options, search) when is_binary(team_key) do
    with {:ok, team} <- resolve_team(options) do
      Linear.projects_by_team(team.id, %{search: search})
    end
  end

  defp update_candidates(_options, _search), do: Linear.workspace_projects()

  defp resolve_update_project(projects, search, options) do
    matches =
      case Enum.filter(projects, &Project.matches_attributes?(&1, search, [:id, :url])) do
        [] -> Enum.filter(projects, &(Project.match_score?(&1, search) == 100))
        references -> references
      end

    case Enum.uniq_by(matches, & &1.id) do
      [] -> resolve_project(projects, search, options)
      [project] -> {:ok, project}
      ambiguous -> disambiguate_update_project(ambiguous, search, options)
    end
  end

  defp disambiguate_update_project(projects, search, options) do
    if Output.json?(options) do
      {:error,
       {:smells_bad,
        "Ambiguous project match for #{inspect(search)}. Use a project ID or --team."}}
    else
      projects
      |> Enum.with_index(1)
      |> Enum.each(fn {project, number} ->
        Prompt.say("#{number}. #{project.name} (#{project.id})")
      end)

      with answer when is_binary(answer) <-
             Prompt.ask("Choose a project by number (Enter to cancel)"),
           {number, ""} when number > 0 <- Integer.parse(answer),
           {:ok, project} <- Enum.fetch(projects, number - 1) do
        {:ok, project}
      else
        _ -> {:error, {:smells_bad, "No project selected."}}
      end
    end
  end

  defp resolve_team(options) do
    key = options.team || Profiles.default_team()

    if Output.json?(options) do
      strict_team(key)
    else
      {:ok, WhatFor.team_for(key)}
    end
  end

  defp strict_team(nil) do
    case Linear.my_teams() do
      {:ok, [team]} -> {:ok, team}
      {:ok, []} -> {:error, {:smells_bad, "JSON output requires --team or an active profile"}}
      {:ok, _teams} -> {:error, {:smells_bad, "JSON output requires --team or an active profile"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp strict_team(key) do
    case Linear.find_team(key) do
      {:ok, team} -> {:ok, team}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_project(projects, search, options) do
    if Output.json?(options) do
      case Projects.project_for_strict(projects, search) do
        nil ->
          {:error,
           {:smells_bad, "JSON output requires an exact project match for #{inspect(search)}"}}

        project ->
          {:ok, project}
      end
    else
      case Projects.project_for(projects, search) do
        nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
        project -> {:ok, project}
      end
    end
  end

  defp listed_projects(nil, flags, options), do: projects_for(flags, options)

  defp listed_projects(projects, _flags, %{team: key}) when is_binary(key) do
    {:ok, Enum.filter(projects, &Enum.any?(&1.teams, fn team -> team_matches?(team, key) end))}
  end

  defp listed_projects(projects, %{mine: true}, _options) do
    with {:ok, teams} <- Linear.my_teams() do
      ids = Enum.map(teams, & &1.id)
      {:ok, Enum.filter(projects, &Enum.any?(&1.teams, fn team -> team.id in ids end))}
    end
  end

  defp listed_projects(projects, _flags, _options), do: {:ok, projects}

  defp team_matches?(team, key) do
    Enum.any?([team.id, team.key], &(String.downcase(&1 || "") == String.downcase(key)))
  end

  defp projects_for(flags, %{team: team_key}) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key) do
      Linear.projects_by_team(team.id, %{with_updates: flags.updates})
    end
  end

  defp projects_for(%{mine: true} = flags, _options),
    do: Linear.my_projects(%{with_updates: flags.updates})

  defp projects_for(flags, _options), do: Linear.projects(%{with_updates: flags.updates})
end
