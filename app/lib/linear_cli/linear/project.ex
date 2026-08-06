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
      manual LinearCli.Linear.Project.Read.ByTeam
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :content, :string, public?: true
    attribute :slug_id, :string, public?: true
    attribute :description, :string, public?: true
    attribute :url, :string, public?: true
  end

  @base_fields "id name content slugId description url createdAt updatedAt"

  @doc "GraphQL field selection for a project's own fields (Ruby: Project::Base)."
  def base_fields, do: @base_fields

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      name: map["name"],
      content: map["content"],
      slug_id: map["slugId"],
      description: map["description"],
      url: map["url"]
    )
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

  # Ruby's Team#projects fetches a single page of 100, no cursor loop.
  @document """
  query($teamId: String!) {
    team(id: $teamId) {
      projects(first: 100) {
        nodes { #{Project.base_fields()} }
      }
    }
  }
  """

  def read(query, _ecto_query, _opts, _context) do
    team_id = query.arguments.team_id

    with {:ok, %{"team" => %{"projects" => %{"nodes" => nodes}}}} <-
           Api.call(@document, %{"teamId" => team_id}) do
      {:ok, Enum.map(nodes, &Project.from_map/1)}
    end
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
