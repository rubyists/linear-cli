defmodule LinearCli.CLI.Issue.Creation do
  @moduledoc """
  Interactive and non-interactive issue creation.

  Extracted from the former `LinearCli.CLI.IssueHelpers`. The single public
  function, `make_da_issue!/1`, creates a new Linear issue by resolving
  title, description, team, labels, and project either interactively (when
  `--yes` is not given) or strictly from provided options (when `--yes` is
  set).

  Profile defaults (active team/project) are consulted before interactive
  prompting when options are omitted.

  Ported from `CLI::Issue#make_da_issue!`.

  ## Return convention

  Returns `{:ok, issue}` on success or `{:error, reason}` on failure (never
  raises). User-visible failures use `{:error, {:smells_bad, message}}`.
  """

  alias LinearCli.CLI.{Projects, WhatFor}
  alias LinearCli.{Linear, Profiles}

  @doc """
  Creates a new issue, resolving every field that wasn't already given in
  `opts` interactively (title, description, team, labels, project - via
  `LinearCli.CLI.WhatFor`/`LinearCli.CLI.Projects`).

  `opts` (Ruby's `**options`): `:title`, `:description`, `:team`, `:labels`,
  `:project`. `:team`/`:project`, if omitted, fall back to
  `LinearCli.Profiles.default_team/0`/`default_project/0` (the active
  profile, if any) before `WhatFor.team_for/1`/`Projects.project_for/2`'s
  own interactive prompting kicks in.

  When `opts[:yes]` is truthy, all fields must be supplied (no interactive
  prompts); missing required fields return `{:error, {:smells_bad, message}}`.

  Ported from `CLI::Issue#make_da_issue!`.
  """
  @spec make_da_issue!(keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def make_da_issue!(opts \\ []) do
    if opts[:yes], do: make_da_issue_no_prompts!(opts), else: make_da_issue_interactive!(opts)
  end

  defp make_da_issue_interactive!(opts) do
    title = WhatFor.title_for(opts[:title])
    description = WhatFor.description_for(opts[:description])
    team = WhatFor.team_for(opts[:team] || Profiles.default_team())
    labels = WhatFor.labels_for(team, opts[:labels])
    project_search = opts[:project] || Profiles.default_project()

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: project_search}) do
      project = Projects.project_for(projects, project_search)
      label_ids = Enum.map(labels, & &1.id)
      params = maybe_put_project_id(%{label_ids: label_ids}, project)

      Linear.create_issue(title, description, team.id, params)
    end
  end

  defp make_da_issue_no_prompts!(opts) do
    with {:ok, title} <- require_field(opts[:title], "--title"),
         {:ok, description} <- require_field(opts[:description], "--description"),
         {:ok, team} <- resolve_team_strict(opts[:team] || Profiles.default_team()) do
      labels =
        case opts[:labels] do
          nil -> []
          [] -> []
          labels -> WhatFor.labels_for(team, labels)
        end

      project_search = opts[:project] || Profiles.default_project()

      with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: project_search}) do
        project =
          if project_search,
            do: Projects.project_for_strict(projects, project_search),
            else: nil

        label_ids = Enum.map(labels, & &1.id)
        params = maybe_put_project_id(%{label_ids: label_ids}, project)
        Linear.create_issue(title, description, team.id, params)
      end
    end
  end

  defp require_field(nil, flag),
    do: {:error, {:smells_bad, "#{flag} is required with --yes"}}

  defp require_field(value, _flag), do: {:ok, value}

  defp resolve_team_strict(nil) do
    case Linear.my_teams() do
      {:ok, [team]} ->
        {:ok, team}

      {:ok, []} ->
        {:error, {:smells_bad, "--team is required (you belong to no teams)"}}

      {:ok, _teams} ->
        {:error, {:smells_bad, "--team is required when you belong to multiple teams"}}

      {:error, reason} ->
        {:error, {:smells_bad, "Could not fetch teams: #{inspect(reason)}"}}
    end
  end

  defp resolve_team_strict(key) do
    case Linear.find_team(key) do
      {:ok, team} -> {:ok, team}
      {:error, _reason} -> {:error, {:smells_bad, "--team #{inspect(key)} not found"}}
    end
  end

  defp maybe_put_project_id(params, nil), do: params
  defp maybe_put_project_id(params, project), do: Map.put(params, :project_id, project.id)
end
