defmodule LinearCli.CLI.Commands.Projects do
  @moduledoc """
  Project commands: list, favorite, unfavorite, and update.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/project/.
  """

  alias LinearCli.CLI.{Display, Projects, Prompt, WhatFor}
  alias LinearCli.{Favorites, Linear, Profiles}

  @doc "Ported from commands/project/list.rb. Ruby's `--mine` defaults false."
  def project_list(%{flags: flags, options: options}) do
    with {:ok, projects} <- projects_for(flags, options) do
      Display.show(filter_favorites(projects, flags.all, "project", & &1.id), %{
        output: options.output
      })

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
    team = WhatFor.team_for(options.team || Profiles.default_team())

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         project when not is_nil(project) <- Projects.project_for(projects, search) do
      Favorites.add("project", project.id)
      Prompt.ok("Favorited project #{project.name}")
      :ok
    else
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Un-favorites a project."
  def project_unfavorite(%{args: %{project: search}, options: options}) do
    team = WhatFor.team_for(options.team || Profiles.default_team())

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         project when not is_nil(project) <- Projects.project_for(projects, search) do
      Favorites.remove("project", project.id)
      Prompt.ok("Un-favorited project #{project.name}")
      :ok
    else
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
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
    team = WhatFor.team_for(options.team || Profiles.default_team())

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         project when not is_nil(project) <- Projects.project_for(projects, search),
         {:ok, update} <-
           Linear.post_project_update(project.id, options.body, %{health: options.health}) do
      Display.show(update, %{output: options.output})
      :ok
    else
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp projects_for(_flags, %{team: team_key}) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key) do
      Linear.projects_by_team(team.id)
    end
  end

  defp projects_for(%{mine: true}, _options), do: Linear.my_projects()
  defp projects_for(_flags, _options), do: Linear.projects()

  # Once any favorite of `kind` exists, narrows `records` down to just
  # those (matched via `key_fun`) - invisible to anyone who's never
  # favorited anything, since an empty favorites list leaves `records`
  # untouched. `all?` (the new `--all` flag) always shows everything,
  # bypassing the favorites lookup entirely.
  defp filter_favorites(records, true, _kind, _key_fun), do: records

  defp filter_favorites(records, _all?, kind, key_fun) do
    case Favorites.list(kind) do
      [] -> records
      favorite_values -> Enum.filter(records, &(key_fun.(&1) in favorite_values))
    end
  end
end
