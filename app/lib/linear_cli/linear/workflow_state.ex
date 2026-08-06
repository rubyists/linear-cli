defmodule LinearCli.Linear.WorkflowState do
  @moduledoc """
  A Linear workflow state (e.g. "In Progress", "Done").
  Ported from vendor/ruby-linear-cli/lib/linear/models/workflow_state.rb.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :by_team do
      argument :team_id, :string, allow_nil?: false
      manual LinearCli.Linear.WorkflowState.Read.ByTeam
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :position, :float, public?: true
    attribute :type, :string, public?: true
    attribute :description, :string, public?: true
  end

  @base_fields "id name position type description createdAt updatedAt"

  @doc "GraphQL field selection for a workflow state's own fields (Ruby: WorkflowState::Base)."
  def base_fields, do: @base_fields

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      name: map["name"],
      position: map["position"],
      type: map["type"],
      description: map["description"]
    )
  end
end

defmodule LinearCli.Linear.WorkflowState.Read.ByTeam do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.WorkflowState

  # Ported from Team#workflow_states_query - single page, no cursor loop.
  @document """
  query($teamId: String!) {
    team(id: $teamId) {
      states {
        nodes { #{WorkflowState.base_fields()} }
      }
    }
  }
  """

  def read(query, _ecto_query, _opts, _context) do
    team_id = query.arguments.team_id

    with {:ok, %{"team" => %{"states" => %{"nodes" => nodes}}}} <-
           Api.call(@document, %{"teamId" => team_id}) do
      {:ok, Enum.map(nodes, &WorkflowState.from_map/1)}
    end
  end
end
