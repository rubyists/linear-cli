defmodule LinearCli.CLI.Commands.Issues.Filter do
  @moduledoc false

  alias LinearCli.CLI.Projects
  alias LinearCli.{Linear, Profiles}

  @doc "Builds the shared issue-list input from CLI flags and options."
  def build_input(flags, options, ids \\ [], opts \\ []) do
    no_profile = Map.get(flags, :no_profile, false)
    team_key = Map.get(options, :team) || unless no_profile, do: Profiles.default_team()

    project_source =
      Map.get(options, :project) || unless no_profile, do: Profiles.default_project()

    project_resolution = Keyword.get(opts, :project_resolution, :permissive)

    with {:ok, project_id} <- resolve_project_id(project_source, team_key, project_resolution) do
      labels = Map.get(options, :labels) || []

      {:ok,
       %{
         ids: ids,
         mine: not Map.get(flags, :no_mine, false),
         unassigned: Keyword.get(opts, :unassigned, Map.get(flags, :unassigned, false)),
         assignee: Map.get(options, :assignee),
         team_key: team_key,
         project_id: project_id,
         all: Map.get(flags, :all, false),
         state: Map.get(options, :state) || [],
         status: Map.get(options, :status) || [],
         labels: labels,
         include_labels:
           Keyword.get(
             opts,
             :include_labels,
             Map.get(flags, :include_labels, false) || labels != []
           ),
         fetch_all_pages: Keyword.get(opts, :fetch_all_pages, false)
       }}
    end
  end

  defp resolve_project_id(nil, _team_key, _resolution), do: {:ok, nil}

  defp resolve_project_id(search, team_key, resolution) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key),
         {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}) do
      resolve_project_match(projects, search, resolution)
    end
  end

  defp resolve_project_id(search, _team_key, resolution) do
    with {:ok, projects} <- Linear.projects() do
      resolve_project_match(projects, search, resolution)
    end
  end

  defp resolve_project_match(projects, search, :permissive) do
    case Projects.project_for(projects, search) do
      nil -> {:ok, nil}
      project -> {:ok, project.id}
    end
  end

  defp resolve_project_match(projects, search, :strict) do
    case Projects.project_for_strict(projects, search) do
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
      project -> {:ok, project.id}
    end
  end
end
