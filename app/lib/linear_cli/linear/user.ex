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
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :email, :string, public?: true
    attribute :teams, {:array, :term}, public?: true, default: []
  end

  @base_fields "id name email"

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

    with {:ok, %{"viewer" => viewer}} <- Api.call(document) do
      {:ok, [User.from_map(viewer)]}
    end
  end
end
