defmodule LinearCli.Linear.Label do
  @moduledoc """
  A Linear issue label. Ported from vendor/ruby-linear-cli/lib/linear/models/label.rb.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :by_names do
      argument :names, {:array, :string}, allow_nil?: false
      manual LinearCli.Linear.Label.Read.ByNames
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :description, :string, public?: true
    attribute :is_group, :boolean, public?: true
  end

  @base_fields "id description name isGroup createdAt updatedAt"

  @doc "GraphQL field selection for a label's own fields (Ruby: Label::Base)."
  def base_fields, do: @base_fields

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      name: map["name"],
      description: map["description"],
      is_group: map["isGroup"]
    )
  end
end

defmodule LinearCli.Linear.Label.Read.ByNames do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.Label

  @document """
  query($names: [String!]) {
    issueLabels(filter: { name: { in: $names } }) {
      edges { node { #{Label.base_fields()} } }
    }
  }
  """

  def read(query, _ecto_query, _opts, _context) do
    names = query.arguments.names

    with {:ok, %{"issueLabels" => %{"edges" => edges}}} <-
           Api.call(@document, %{"names" => names}) do
      {:ok, Enum.map(edges, &Label.from_map(&1["node"]))}
    end
  end
end
