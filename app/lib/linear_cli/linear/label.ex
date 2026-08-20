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

    # Ruby: Team#labels, as called by WhatFor#labels_for(team, nil) for its
    # interactive multi_select fallback. Not one of the two "already exist"
    # interfaces this phase was told about (Team.mine / Label.find_all_by_name)
    # - added here because that fallback has no other way to list a team's
    # labels without it.
    read :by_team do
      argument :team_id, :string, allow_nil?: false
      manual LinearCli.Linear.Label.Read.ByTeam
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

    case Api.call(@document, %{"names" => names}) do
      {:ok, %{"issueLabels" => %{"edges" => edges}}} ->
        {:ok, Enum.map(edges, &Label.from_map(&1["node"]))}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, {:http_error, status, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule LinearCli.Linear.Label.Read.ByTeam do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.Label

  # Ruby: Team#label_query / Team#labels - team(id:)'s labels, filtered down
  # (server-side, same BaseFilter Ruby uses) to exclude release/platform
  # labels, and (client-side, matching Ruby's `filter_map`) to exclude group
  # labels and labels that belong to a group (have a parent) - Ruby's
  # `next if label[:isGroup] || label[:parent]`.
  @document """
  query($teamId: String!) {
    team(id: $teamId) {
      labels(
        first: 100
        filter: {
          and: [
            { name: { notEndsWith: " Releases" } }
            { name: { notEndsWith: "-ios" } }
            { name: { notEndsWith: "-android" } }
          ]
        }
      ) {
        nodes { #{Label.base_fields()} parent { id } }
      }
    }
  }
  """

  def read(query, _ecto_query, _opts, _context) do
    team_id = query.arguments.team_id

    case Api.call(@document, %{"teamId" => team_id}) do
      {:ok, %{"team" => %{"labels" => %{"nodes" => nodes}}}} ->
        labels =
          nodes
          |> Enum.reject(&(&1["isGroup"] || &1["parent"]))
          |> Enum.map(&Label.from_map/1)

        {:ok, labels}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, {:http_error, status, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
