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

    # Ruby: BaseModel::ClassMethods#find, as called by WhatFor#team_for(key).
    # Not one of the two "already exist" interfaces this phase was told about
    # (Team.mine / Label.find_all_by_name) - added here because team_for's
    # key-given branch has no other way to resolve an arbitrary team id/key
    # to a Team without it. Follows the same single-node-by-id shape as
    # LinearCli.Linear.Issue.Read.List's find_document, and the same
    # `get?: true` + manual-read-returns-a-list convention already proven by
    # LinearCli.Linear.User.Read.Me.
    read :find do
      argument :id, :string, allow_nil?: false
      get? true
      manual LinearCli.Linear.Team.Read.Find
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

defmodule LinearCli.Linear.Team.Read.Find do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.Team

  # Ruby: BaseModel::ClassMethods#find - team(id: $id) node lookup,
  # full_fragment (base fields plus projects).
  def read(query, _ecto_query, _opts, _context) do
    id = query.arguments.id

    case Api.call(document(), %{"id" => id}) do
      {:ok, %{"team" => nil}} ->
        {:ok, []}

      {:ok, %{"team" => team_map}} ->
        {:ok, [Team.from_map(team_map)]}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, {:http_error, status, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A function, not a module attribute: Team.full_fields/0 reaches into
  # Project (another file), so it must be evaluated at call time - see house
  # rule on cross-file compile-time module attribute evaluation order.
  defp document do
    "query($id: String!) { team(id: $id) { #{Team.full_fields()} } }"
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
