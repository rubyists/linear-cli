defmodule LinearCli.Linear.User do
  @moduledoc """
  A Linear user. Ported from vendor/ruby-linear-cli/lib/linear/models/user.rb.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :me do
      get? true
      manual LinearCli.Linear.User.Read.Me
    end

    read :by_team do
      argument :team_id, :string, allow_nil?: false
      manual LinearCli.Linear.User.Read.ByTeam
    end

    read :by_team_for_lookup do
      argument :team_id, :string, allow_nil?: false
      manual LinearCli.Linear.User.Read.ByTeamForLookup
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :display_name, :string, public?: true
    attribute :email, :string, public?: true
    attribute :teams, {:array, :term}, public?: true, default: []
  end

  @base_fields "id name displayName email"

  @doc "GraphQL field selection for a user's own fields (no nested teams)."
  def base_fields, do: @base_fields

  @doc "GraphQL field selection including the user's teams (Ruby: User.base_fragment)."
  def fields_with_teams do
    "#{@base_fields} teams { nodes { #{LinearCli.Linear.Team.base_fields()} } }"
  end

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      name: map["name"],
      display_name: map["displayName"],
      email: map["email"],
      teams: Enum.map(get_in(map, ["teams", "nodes"]) || [], &LinearCli.Linear.Team.from_map/1)
    )
  end
end

defmodule LinearCli.Linear.User.Read.Me do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.User

  def read(_query, _ecto_query, _opts, _context) do
    document = "{ viewer { #{User.fields_with_teams()} } }"

    case Api.call(document) do
      {:ok, %{"viewer" => viewer}} when is_map(viewer) ->
        {:ok, [User.from_map(viewer)]}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, {:http_error, status, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule LinearCli.Linear.User.Read.ByTeam do
  @moduledoc false
  use Ash.Resource.ManualRead

  def read(query, ecto_query, opts, context) do
    LinearCli.Linear.User.Read.ByTeamForLookup.read(query, ecto_query, opts, context)
  end
end

defmodule LinearCli.Linear.User.Read.ByTeamForLookup do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.User

  @document """
  query($id: String!, $after: String) {
    team(id: $id) {
      members(first: 50, after: $after) {
        edges { node { #{User.base_fields()} } cursor }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
  """

  def read(query, _ecto_query, _opts, _context) do
    page(query.arguments.team_id, nil, [])
  end

  defp page(team_id, after_cursor, acc) do
    case Api.call(@document, %{"id" => team_id, "after" => after_cursor}) do
      {:ok, %{"team" => %{"members" => members}}} when is_map(members) ->
        continue_page(members, team_id, after_cursor, acc)

      {:ok, _response} when is_nil(after_cursor) ->
        {:ok, acc}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, {:http_error, status, _body}} ->
        {:error, {:http_error, status}}

      error ->
        error
    end
  end

  defp continue_page(members, team_id, after_cursor, acc) do
    nodes = Enum.map(members["edges"] || [], &User.from_map(&1["node"]))
    acc = acc ++ nodes
    page_info = members["pageInfo"] || %{}

    if page_info["hasNextPage"] == true do
      next_cursor = page_info["endCursor"]

      if next_cursor == after_cursor do
        {:error, {:non_advancing_cursor, next_cursor}}
      else
        page(team_id, next_cursor, acc)
      end
    else
      {:ok, acc}
    end
  end
end
