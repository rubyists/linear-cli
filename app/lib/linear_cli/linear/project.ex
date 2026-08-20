defmodule LinearCli.Linear.Project do
  @moduledoc """
  A Linear project. Ported from vendor/ruby-linear-cli/lib/linear/models/project.rb.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :all do
      manual LinearCli.Linear.Project.Read.All
    end

    read :mine do
      manual LinearCli.Linear.Project.Read.Mine
    end

    read :by_team do
      argument :team_id, :string, allow_nil?: false
      argument :search, :string
      manual LinearCli.Linear.Project.Read.ByTeam
    end

    # New in Phase 7 - Ruby has no equivalent. Backs the monthly rollover's
    # auto-create-target-project behavior.
    create :create do
      argument :name, :string, allow_nil?: false
      argument :team_id, :string, allow_nil?: false
      manual LinearCli.Linear.Project.Create
    end

    # New in Phase 7 - Ruby has no equivalent. Finds a project by exact
    # name, fetching its teams too so the rollover can create next month's
    # project on the same team without a separate lookup.
    read :by_name do
      argument :name, :string, allow_nil?: false
      get? true
      manual LinearCli.Linear.Project.Read.ByName
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :content, :string, public?: true
    attribute :slug_id, :string, public?: true
    attribute :description, :string, public?: true
    attribute :url, :string, public?: true
    attribute :teams, {:array, :term}, public?: true, default: []
  end

  @base_fields "id name content slugId description url createdAt updatedAt"

  @doc "GraphQL field selection for a project's own fields (Ruby: Project::Base)."
  def base_fields, do: @base_fields

  @doc "GraphQL field selection including the project's teams. New in Phase 7."
  def fields_with_teams do
    "#{@base_fields} teams { nodes { #{LinearCli.Linear.Team.base_fields()} } }"
  end

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      name: map["name"],
      content: map["content"],
      slug_id: map["slugId"],
      description: map["description"],
      url: map["url"],
      teams: Enum.map(get_in(map, ["teams", "nodes"]) || [], &LinearCli.Linear.Team.from_map/1)
    )
  end

  @doc """
  Ported from Ruby's `Project#slug`: the URL's basename with the trailing
  `-slugId` suffix stripped (first occurrence only, matching Ruby's `sub`).
  """
  def slug(%__MODULE__{url: url, slug_id: slug_id}) do
    url
    |> to_string()
    |> Path.basename()
    |> String.replace("-#{slug_id}", "", global: false)
  end

  @doc """
  Ported from Ruby's `Project#match_score?`. Scores how well `string`
  matches this project:

    * `100` - `string` exactly (case-insensitively) equals the project's
      `id` or `url`, or its slugified form equals `slug/1`, or it
      case-insensitively equals the project's `name`
    * `75` - the project's `name` contains `string` (case-sensitive, as in
      Ruby), or `slug/1` contains the downcased `string`
    * `50` - the project's `description` contains the downcased `string`
      (case-insensitive)
    * `0` - otherwise
  """
  def match_score?(%__MODULE__{} = project, string) when is_binary(string) do
    cond do
      matches_attributes?(project, string, [:id, :url]) -> 100
      exact_name_or_slug_match?(project, string) -> 100
      name_or_slug_contains?(project, string) -> 75
      description_contains?(project, string) -> 50
      true -> 0
    end
  end

  @doc """
  Ported from Ruby's `Project#matches_attributes?`. Does `string`
  case-insensitively equal any of the project's `attrs` field values?
  """
  def matches_attributes?(%__MODULE__{} = project, string, attrs) do
    Enum.any?(attrs, fn attr ->
      case Map.get(project, attr) do
        value when is_binary(value) ->
          normalize_match_value(attr, value) == normalize_match_value(attr, string)

        _ ->
          false
      end
    end)
  end

  defp normalize_match_value(:url, value) do
    value
    |> String.trim_trailing("/")
    |> String.trim_trailing("/issues")
    |> String.downcase()
  end

  defp normalize_match_value(_attr, value), do: String.downcase(value)

  defp exact_name_or_slug_match?(project, string) do
    downed = String.downcase(string)
    slugified = downed |> String.split() |> Enum.join("-")

    slugified == slug(project) or downed == String.downcase(project.name || "")
  end

  defp name_or_slug_contains?(project, string) do
    String.contains?(project.name || "", string) or
      String.contains?(slug(project), String.downcase(string))
  end

  defp description_contains?(project, string) do
    String.contains?(String.downcase(project.description || ""), String.downcase(string))
  end
end

defmodule LinearCli.Linear.Project.Read.All do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Linear.{Paginate, Project}

  @document """
  query($first: Int!, $after: String) {
    projects(first: $first, after: $after) {
      edges { node { #{Project.base_fields()} } cursor }
      pageInfo { hasNextPage endCursor }
    }
  }
  """

  def read(_query, _ecto_query, _opts, _context) do
    Paginate.all(
      @document,
      "projects",
      fn after_cursor -> %{"first" => 50, "after" => after_cursor} end,
      &Project.from_map/1
    )
  end
end

defmodule LinearCli.Linear.Project.Read.ByTeam do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.Project

  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  @slugged_reference ~r/^(.*)-([[:alnum:]]{12})$/

  @document """
  query($teamId: String!, $after: String) {
    team(id: $teamId) {
      projects(first: 100, after: $after) {
        nodes { #{Project.base_fields()} }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
  """

  @search_document """
  query($teamId: String!, $filter: ProjectFilter!) {
    team(id: $teamId) {
      projects(first: 100, filter: $filter) {
        nodes { #{Project.base_fields()} }
      }
    }
  }
  """

  def read(query, _ecto_query, _opts, _context) do
    team_id = query.arguments.team_id

    case Map.get(query.arguments, :search) do
      search when is_binary(search) and search not in ["", "-"] ->
        search(team_id, search)

      _ ->
        all(team_id)
    end
  end

  defp search(team_id, search) do
    variables = %{"teamId" => team_id, "filter" => project_filter(search)}

    with {:ok, projects} <- fetch(@search_document, variables) do
      if projects == [], do: all(team_id), else: {:ok, projects}
    end
  end

  defp all(team_id), do: page(team_id, nil, [])

  defp page(team_id, after_cursor, acc) do
    variables =
      if after_cursor,
        do: %{"teamId" => team_id, "after" => after_cursor},
        else: %{"teamId" => team_id}

    with {:ok, %{"team" => %{"projects" => projects}}} <- Api.call(@document, variables) do
      acc = acc ++ Enum.map(projects["nodes"] || [], &Project.from_map/1)

      case projects["pageInfo"] do
        %{"hasNextPage" => true, "endCursor" => cursor} when is_binary(cursor) ->
          page(team_id, cursor, acc)

        _ ->
          {:ok, acc}
      end
    else
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, {:http_error, status, _body}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch(document, variables) do
    with {:ok, %{"team" => %{"projects" => %{"nodes" => nodes}}}} <-
           Api.call(document, variables) do
      {:ok, Enum.map(nodes, &Project.from_map/1)}
    else
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, {:http_error, status, _body}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp project_filter(search) do
    reference = project_reference(search)
    {name, slug_id} = reference_terms(reference)

    [
      project_id_filter(search),
      %{"name" => %{"containsIgnoreCase" => search}},
      %{"name" => %{"containsIgnoreCase" => name}},
      %{"slugId" => %{"eqIgnoreCase" => slug_id}}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> then(&%{"or" => &1})
  end

  defp project_reference(search) do
    case Regex.run(~r{/project/([^/]+)}, search, capture: :all_but_first) do
      [reference] -> reference
      _ -> search
    end
  end

  defp reference_terms(reference) do
    case Regex.run(@slugged_reference, reference, capture: :all_but_first) do
      [slug, slug_id] -> {String.replace(slug, "-", " "), slug_id}
      _ -> {String.replace(reference, "-", " "), reference}
    end
  end

  defp project_id_filter(search) do
    if Regex.match?(@uuid, search), do: %{"id" => %{"eq" => search}}
  end
end

defmodule LinearCli.Linear.Project.Read.ByName do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.Project

  def read(query, _ecto_query, _opts, _context) do
    name = query.arguments.name

    with {:ok, %{"projects" => %{"nodes" => nodes}}} <-
           Api.call(document(), %{"name" => name}) do
      {:ok, Enum.map(nodes, &Project.from_map/1)}
    else
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, {:http_error, status, _body}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # A function, not a module attribute: Project.fields_with_teams/0 reaches
  # into Team (another file), so it must be evaluated at call time.
  defp document do
    """
    query($name: String!) {
      projects(filter: {name: {eq: $name}}, first: 1) {
        nodes { #{Project.fields_with_teams()} }
      }
    }
    """
  end
end

defmodule LinearCli.Linear.Project.Create do
  @moduledoc false
  use Ash.Resource.ManualCreate

  alias LinearCli.Api
  alias LinearCli.Linear.Project

  # projectCreate mutation. `teamIds` is a list per the schema, even though
  # this action only ever supplies one - see schema/LinearAPI.graphql.
  def create(changeset, _opts, _context) do
    args = changeset.arguments
    input = %{"name" => args.name, "teamIds" => [args.team_id]}

    case Api.call(document(), %{"input" => input}) do
      {:ok, %{"projectCreate" => %{"project" => project_map}}} when is_map(project_map) ->
        {:ok, Project.from_map(project_map)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp document do
    "mutation($input: ProjectCreateInput!) { projectCreate(input: $input) { project { #{Project.base_fields()} } } }"
  end
end

defmodule LinearCli.Linear.Project.Read.Mine do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Linear.{Project, User}

  # Ruby: Project.mine = User.me.teams.flat_map(&:projects) - fully serial,
  # one request per team. Each team's projects are an independent GraphQL
  # call, so fan them out concurrently instead.
  def read(_query, _ecto_query, _opts, _context) do
    with {:ok, user} <- Ash.read_one(Ash.Query.for_read(User, :me)) do
      user.teams
      |> Task.async_stream(&fetch_team_projects/1, timeout: 30_000)
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, {:ok, projects}}, {:ok, acc} -> {:cont, {:ok, acc ++ projects}}
        {:ok, {:error, reason}}, {:ok, _acc} -> {:halt, {:error, reason}}
        {:exit, reason}, {:ok, _acc} -> {:halt, {:error, {:task_exit, reason}}}
      end)
    end
  end

  # Ash.read/1 (not read!/1) - a raise inside an async task would surface as
  # an unhelpful {:exit, reason} to the caller instead of a clean error tuple.
  defp fetch_team_projects(team) do
    Ash.read(Ash.Query.for_read(Project, :by_team, %{team_id: team.id}))
  end
end
