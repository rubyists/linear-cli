defmodule LinearCli.Linear do
  @moduledoc """
  Domain for everything backed by the Linear GraphQL API.

  There's no real data layer here - Linear's API is the backing store, so
  each resource's actions are manual actions calling `LinearCli.Api`
  directly. See `documents/initial-plan.adoc` (Architecture Decisions ->
  Domain layer: Ash).
  """

  use Ash.Domain

  resources do
    resource LinearCli.Linear.User do
      define :me, action: :me, get?: true
    end

    resource LinearCli.Linear.Team do
      define :teams, action: :all
      define :my_teams, action: :mine
    end

    resource LinearCli.Linear.Project do
      define :projects, action: :all
      define :my_projects, action: :mine
    end

    resource LinearCli.Linear.Issue do
      define :issues, action: :list
    end

    resource LinearCli.Linear.Label do
      define :labels_by_names, action: :by_names, args: [:names]
    end

    resource LinearCli.Linear.WorkflowState do
      define :workflow_states_by_team, action: :by_team, args: [:team_id]
    end

    resource LinearCli.Linear.Comment
  end
end
