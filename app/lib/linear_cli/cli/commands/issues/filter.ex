defmodule LinearCli.CLI.Commands.Issues.Filter do
  @moduledoc false

  alias LinearCli.CLI.{Projects, Prompt}
  alias LinearCli.{Linear, Profiles}

  @doc "Builds the shared issue-list input from CLI flags and options."
  def build_input(flags, options, ids \\ [], opts \\ []) do
    {team_key, project_source} = filter_sources(flags, options)
    project_resolution = Keyword.get(opts, :project_resolution, :permissive)

    with {:ok, project_id} <- resolve_project_id(project_source, team_key, project_resolution),
         {:ok, assignee_id} <- resolve_assignee_id(Map.get(options, :assignee), team_key, opts) do
      {:ok, build_issue_input(flags, options, ids, opts, team_key, project_id, assignee_id)}
    end
  end

  defp filter_sources(flags, options) do
    no_profile = Map.get(flags, :no_profile, false)
    team = Map.get(options, :team) || profile_default(no_profile, &Profiles.default_team/0)

    project =
      Map.get(options, :project) || profile_default(no_profile, &Profiles.default_project/0)

    {team, project}
  end

  defp profile_default(true, _default), do: nil
  defp profile_default(false, default), do: default.()

  defp build_issue_input(flags, options, ids, opts, team_key, project_id, assignee_id) do
    labels = Map.get(options, :labels) || []

    %{
      ids: ids,
      mine: not Map.get(flags, :no_mine, false),
      unassigned: Keyword.get(opts, :unassigned, Map.get(flags, :unassigned, false)),
      assignee_id: assignee_id,
      assigned_only: Keyword.get(opts, :assigned_only, false),
      team_key: team_key,
      project_id: project_id,
      all: Map.get(flags, :all, false),
      state: Map.get(options, :state) || [],
      status: Map.get(options, :status) || [],
      labels: labels,
      include_labels:
        Keyword.get(opts, :include_labels, Map.get(flags, :include_labels, false) || labels != [])
    }
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
    case Projects.project_scores(projects, search) do
      [] ->
        {:error, {:smells_bad, "No project found matching #{search}"}}

      possibles ->
        case Enum.find(possibles, &(LinearCli.Linear.Project.match_score?(&1, search) == 100)) do
          nil ->
            case Projects.project_for(projects, search) do
              nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
              project -> {:ok, project.id}
            end

          project ->
            {:ok, project.id}
        end
    end
  end

  defp resolve_assignee_id(nil, _team_key, _opts), do: {:ok, nil}

  defp resolve_assignee_id(assignee, _team_key, _opts)
       when not is_binary(assignee) or assignee == "",
       do: {:ok, nil}

  defp resolve_assignee_id(assignee, team_key, opts) do
    if Keyword.get(opts, :resolve_assignee, false) do
      with {:ok, members} <- assignee_members(team_key),
           {:ok, member} <- resolve_assignee_member(members, assignee) do
        {:ok, member.id}
      end
    else
      {:ok, nil}
    end
  end

  defp assignee_members(team_key) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key), do: Linear.team_members(team.id)
  end

  defp assignee_members(nil) do
    with {:ok, teams} <- Linear.teams() do
      teams
      |> Enum.reduce_while({:ok, %{}}, &collect_team_members/2)
      |> members_from_result()
    end
  end

  defp collect_team_members(team, {:ok, members_by_id}) do
    case Linear.team_members(team.id) do
      {:ok, members} ->
        members_by_id =
          Enum.reduce(members, members_by_id, fn member, acc ->
            Map.put(acc, member.id, member)
          end)

        {:cont, {:ok, members_by_id}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp members_from_result({:ok, members_by_id}), do: {:ok, Map.values(members_by_id)}
  defp members_from_result(error), do: error

  defp resolve_assignee_member(members, search) do
    normalized_search = String.downcase(search)
    exact = Enum.filter(members, &assignee_exact_match?(&1, normalized_search))

    case exact do
      [member] ->
        {:ok, member}

      [_ | _] ->
        {:error, ambiguous_assignee_error(exact, search)}

      [] ->
        partial = Enum.filter(members, &assignee_partial_match?(&1, normalized_search))

        case partial do
          [] -> {:error, unknown_assignee_error(members, search)}
          matches -> {:ok, Prompt.select("Assignee:", assignee_choices(matches))}
        end
    end
  end

  defp assignee_exact_match?(member, search) do
    Enum.any?(assignee_names(member), &(String.downcase(&1) == search))
  end

  defp assignee_partial_match?(member, search) do
    Enum.any?(assignee_names(member), &String.starts_with?(String.downcase(&1), search))
  end

  defp assignee_names(member) do
    [Map.get(member, :name), Map.get(member, :display_name)]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp assignee_choices(members) do
    members
    |> Enum.sort_by(&assignee_label/1)
    |> Enum.map(&{assignee_label(&1), &1})
  end

  defp assignee_label(member) do
    case assignee_names(member) do
      [name, display_name] when name != display_name -> "#{name} (#{display_name})"
      [name | _] -> name
      [] -> member.id
    end
  end

  defp ambiguous_assignee_error(members, search) do
    matches = Enum.map_join(assignee_choices(members), ", ", &elem(&1, 0))
    {:smells_bad, "Ambiguous assignee #{inspect(search)}: matches #{matches}"}
  end

  defp unknown_assignee_error(members, search) do
    available = Enum.map_join(assignee_choices(members), ", ", &elem(&1, 0))
    {:smells_bad, "Unknown assignee #{inspect(search)}. Available: #{available}"}
  end
end
