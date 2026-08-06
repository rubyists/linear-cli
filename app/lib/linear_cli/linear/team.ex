defmodule LinearCli.Linear.Team do
  @moduledoc """
  A Linear team. Ported from vendor/ruby-linear-cli/lib/linear/models/team.rb.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :all do
      manual LinearCli.Linear.Team.Read.All
    end

    read :mine do
      manual LinearCli.Linear.Team.Read.Mine
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :key, :string, public?: true
    attribute :name, :string, public?: true
    attribute :description, :string, public?: true
  end

  @base_fields "description id key name createdAt updatedAt"

  @doc "GraphQL field selection for a team's own fields (Ruby: Team::Base)."
  def base_fields, do: @base_fields

  @doc "GraphQL field selection including the team's projects (Ruby: Team.full_fragment)."
  def full_fields do
    "#{@base_fields} projects { nodes { #{LinearCli.Linear.Project.base_fields()} } }"
  end

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      key: map["key"],
      name: map["name"],
      description: map["description"]
    )
  end
end

defmodule LinearCli.Linear.Team.Read.All do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Linear.{Paginate, Team}

  @document """
  query($first: Int!, $after: String) {
    teams(first: $first, after: $after) {
      edges { node { #{Team.base_fields()} } cursor }
      pageInfo { hasNextPage endCursor }
    }
  }
  """

  def read(_query, _ecto_query, _opts, _context) do
    Paginate.all(
      @document,
      "teams",
      fn after_cursor -> %{"first" => 50, "after" => after_cursor} end,
      &Team.from_map/1
    )
  end
end

defmodule LinearCli.Linear.Team.Read.Mine do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Linear.User

  def read(_query, _ecto_query, _opts, _context) do
    with {:ok, user} <- Ash.read_one(Ash.Query.for_read(User, :me)) do
      {:ok, user.teams}
    end
  end
end
