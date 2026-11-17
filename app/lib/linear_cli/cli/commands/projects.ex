defmodule LinearCli.CLI.Commands.Projects do
  @moduledoc """
  Project commands: list, favorite, unfavorite, and update.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/project/.
  """

  alias LinearCli.CLI.{Display, Output, Projects, Prompt, WhatFor}
  alias LinearCli.{Favorites, Linear, Profiles}

  @doc "Ported from commands/project/list.rb. Ruby's `--mine` defaults false."
  def project_list(%{flags: flags, options: options}) do
    with {:ok, cached} <- Favorites.records("project", flags.all),
         {:ok, projects} <- listed_projects(cached, flags, options) do
      Display.show(projects, %{output: options.output})
      :ok
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Favorites a project
  (`LinearCli.Favorites`), resolved against the active team's projects,
  prompting if ambiguous. Team is resolved via `--team`, the active
  profile, or an interactive prompt. Once any project is favorited,
  `project list` defaults to showing just favorites (`--all` overrides).
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
  New in this port - Ruby has no equivalent. Posts a status update
  (Linear's own "Project Update" feature - a journal-style status post,
  not an edit to the project's own fields) via the projectUpdateCreate
  mutation. `PROJECT` is resolved against the active team's projects,
  prompting if ambiguous. Team is resolved via `--team`, the active
  profile, or an interactive prompt.
  """
  def project_update(%{args: %{project: search}, options: options}) do
    with {:ok, team} <- resolve_team(options),
         {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         {:ok, project} <- resolve_project(projects, search, options),
         {:ok, update} <-
           Linear.post_project_update(project.id, options.body, %{health: options.health}) do
      Display.show(update, %{output: options.output})
      :ok
    else
      {:error, reason} -> {:error, reason}
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

  defp projects_for(_flags, %{team: team_key}) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key) do
      Linear.projects_by_team(team.id)
    end
  end

  defp projects_for(%{mine: true}, _options), do: Linear.my_projects()
  defp projects_for(_flags, _options), do: Linear.projects()
end
