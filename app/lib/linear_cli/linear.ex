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
      define :team_members, action: :by_team, args: [:team_id]
    end

    resource LinearCli.Linear.Team do
      define :teams, action: :all
      define :my_teams, action: :mine
      define :find_team, action: :find, args: [:id], get?: true
    end

    resource LinearCli.Linear.Project do
      define :projects, action: :all
      define :my_projects, action: :mine
      define :projects_by_team, action: :by_team, args: [:team_id]
      define :create_project, action: :create, args: [:name, :team_id]
      define :find_project_by_name, action: :by_name, args: [:name], get?: true
    end

    resource LinearCli.Linear.Issue do
      define :issues, action: :list
      define :create_issue, action: :create, args: [:title, :description, :team_id]
      define :assign_issue, action: :assign, args: [:assignee_id]
      define :attach_issue_to_project, action: :attach_to_project, args: [:project_id]
      define :close_issue, action: :close, args: [:state_id]
      define :set_issue_status, action: :set_status, args: [:state_id]
      define :update_issue_description, action: :update_description, args: [:description]
    end

    resource LinearCli.Linear.Label do
      define :labels_by_names, action: :by_names, args: [:names]
      define :labels_by_team, action: :by_team, args: [:team_id]
    end

    resource LinearCli.Linear.WorkflowState do
      define :workflow_states_by_team, action: :by_team, args: [:team_id]
    end

    resource LinearCli.Linear.Comment do
      define :add_comment, action: :create, args: [:issue_identifier, :body]
    end

    resource LinearCli.Linear.ProjectUpdate do
      define :post_project_update, action: :create, args: [:project_id, :body]
    end

    resource LinearCli.Linear.IssueRelation do
      define :issue_relations, action: :list, args: [:issue_id]
      define :create_issue_relation, action: :create, args: [:issue_id, :related_issue_id, :type]
      define :delete_issue_relation, action: :destroy
    end
  end
end
