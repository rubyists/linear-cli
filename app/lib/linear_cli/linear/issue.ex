defmodule LinearCli.Linear.Issue do
  @moduledoc """
  A Linear issue. Ported from vendor/ruby-linear-cli/lib/linear/models/issue.rb
  and lib/linear/operations/issue/list.rb.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :list do
      argument :ids, {:array, :string}, default: []
      argument :mine, :boolean, default: true
      argument :unassigned, :boolean, default: false
      argument :team_key, :string, allow_nil?: true
      argument :project_id, :string, allow_nil?: true
      argument :all, :boolean, default: false
      argument :state, {:array, :string}, default: []
      argument :status, {:array, :string}, default: []
      manual LinearCli.Linear.Issue.Read.List
    end

    # Ruby: Issue::ClassMethods#create(title:, description:, team:, project:, labels: [])
    create :create do
      argument :title, :string, allow_nil?: false
      argument :description, :string, allow_nil?: true
      argument :team_id, :string, allow_nil?: false
      argument :project_id, :string, allow_nil?: true
      argument :label_ids, {:array, :string}, default: []
      manual LinearCli.Linear.Issue.Create
    end

    # Ruby: Issue#assign!(user)
    update :assign do
      argument :assignee_id, :string, allow_nil?: false
      argument :state_id, :string, allow_nil?: true
      manual LinearCli.Linear.Issue.Update.Assign
    end

    # Ruby: Issue#attach_to_project(project)
    update :attach_to_project do
      argument :project_id, :string, allow_nil?: false
      manual LinearCli.Linear.Issue.Update.AttachToProject
    end

    # Ruby: Issue#close! / #close_mutation. One action shape covers both a
    # "close" and a "cancel" workflow transition - which workflow state gets
    # passed in is a later phase's CLI-level concern, not this action's.
    update :close do
      argument :state_id, :string, allow_nil?: false
      argument :trash, :boolean, default: false
      manual LinearCli.Linear.Issue.Update.Close
    end

    update :set_status do
      argument :state_id, :string, allow_nil?: false
      manual LinearCli.Linear.Issue.Update.SetStatus
    end

    update :update_description do
      argument :description, :string, allow_nil?: false
      manual LinearCli.Linear.Issue.Update.UpdateDescription
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :identifier, :string, public?: true
    attribute :title, :string, public?: true
    attribute :branch_name, :string, public?: true
    attribute :description, :string, public?: true
    attribute :assignee, :term, public?: true
    attribute :state, :term, public?: true
    attribute :team, :term, public?: true
    attribute :comments, {:array, :term}, public?: true, default: []
  end

  @issue_fields "id identifier title branchName description createdAt updatedAt"
  @state_fields "id name type"

  @doc "GraphQL field selection for an issue plus its assignee/team (Ruby: Issue.base_fragment)."
  def base_fields do
    "#{@issue_fields} " <>
      "state { #{@state_fields} } " <>
      "assignee { #{LinearCli.Linear.User.fields_with_teams()} } " <>
      "team { #{LinearCli.Linear.Team.base_fields()} }"
  end

  @doc "GraphQL field selection for a fully detailed issue, incl. comments (Ruby: Issue.full_fragment)."
  def full_fields do
    "#{@issue_fields} " <>
      "state { #{@state_fields} } " <>
      "assignee { #{LinearCli.Linear.User.fields_with_teams()} } " <>
      "team { #{LinearCli.Linear.Team.full_fields()} } " <>
      "comments { nodes { #{LinearCli.Linear.Comment.base_fields()} } }"
  end

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      identifier: map["identifier"],
      title: map["title"],
      branch_name: map["branchName"],
      description: map["description"],
      assignee: map["assignee"] && LinearCli.Linear.User.from_map(map["assignee"]),
      state: map["state"] && LinearCli.Linear.WorkflowState.from_map(map["state"]),
      team: map["team"] && LinearCli.Linear.Team.from_map(map["team"]),
      comments:
        Enum.map(
          get_in(map, ["comments", "nodes"]) || [],
          &LinearCli.Linear.Comment.from_map/1
        )
    )
  end
end

defmodule LinearCli.Linear.Issue.Read.List do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.{Issue, Paginate}

  def read(query, _ecto_query, _opts, _context) do
    args = query.arguments

    if args.ids != [] do
      find_by_ids(args.ids)
    else
      list_all(build_filter(args))
    end
  end

  # Ruby: BaseModel::ClassMethods#find - singular `issue(id:)` lookup, full_fragment.
  # A function, not a module attribute: its body reaches into User/Team/Comment
  # (other files), so it must be evaluated at call time, not at compile time of
  # this module - cross-file module-attribute evaluation order isn't guaranteed.
  defp find_document do
    "query($id: String!) { issue(id: $id) { #{Issue.full_fields()} } }"
  end

  # Ruby: BaseModel::ClassMethods#all - paginated `issues(filter:)`, base_fragment.
  defp list_document do
    """
    query($filter: IssueFilter, $first: Int!, $after: String) {
      issues(filter: $filter, first: $first, after: $after) {
        edges { node { #{Issue.base_fields()} } cursor }
        pageInfo { hasNextPage endCursor }
      }
    }
    """
  end

  # Ruby: params[:ids].map { |id| Issue.find(id) } - fully serial. Each id is
  # an independent GraphQL call, so fan them out concurrently instead. Capped
  # at 20 in flight to avoid hammering the API on a very long id list; ordered
  # so results come back in the same order as `ids`, matching Ruby's `.map`.
  defp find_by_ids(ids) do
    ids
    |> Task.async_stream(&fetch_one/1, max_concurrency: min(length(ids), 20), timeout: 30_000)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, issue}}, {:ok, acc} -> {:cont, {:ok, [issue | acc]}}
      {:ok, {:error, reason}}, {:ok, _acc} -> {:halt, {:error, reason}}
      {:exit, reason}, {:ok, _acc} -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> case do
      {:ok, issues} -> {:ok, Enum.reverse(issues)}
      error -> error
    end
  end

  defp fetch_one(id) do
    case Api.call(find_document(), %{"id" => String.upcase(id)}) do
      {:ok, %{"issue" => issue_map}} when is_map(issue_map) -> {:ok, Issue.from_map(issue_map)}
      {:ok, %{"issue" => nil}} -> {:error, {:not_found, id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_all(filter) do
    Paginate.all(
      list_document(),
      "issues",
      fn after_cursor -> %{"filter" => filter, "first" => 50, "after" => after_cursor} end,
      &Issue.from_map/1
    )
  end

  # Ported from Rubyists::Linear::Operations::Issue::List#build_filter. `unassigned`
  # is checked after `mine` here too, so it wins if both are set - same as Ruby.
  # `all: true` removes the completedAt/canceledAt null-checks so closed/cancelled
  # issues are included. A type filter only removes the date guard for the closed
  # state it requests. A friendly-name filter removes both guards because its type
  # is unknown until Linear evaluates it.
  defp build_filter(args) do
    %{}
    |> maybe_put_date_filters(args)
    |> maybe_put_assignee_filter(args)
    |> maybe_put_team_filter(args)
    |> maybe_put_project_filter(args)
    |> maybe_put_state_filter(args)
  end

  @completed_types ~w(completed)
  @cancelled_types ~w(cancelled canceled duplicate)

  defp maybe_put_date_filters(filter, %{all: true}), do: filter

  defp maybe_put_date_filters(filter, %{state: [_ | _] = states}) do
    filter
    |> maybe_put_completed_date_filter(states)
    |> maybe_put_cancelled_date_filter(states)
  end

  defp maybe_put_date_filters(filter, %{status: [_ | _]}), do: filter

  defp maybe_put_date_filters(filter, _args) do
    Map.merge(filter, %{"completedAt" => %{"null" => true}, "canceledAt" => %{"null" => true}})
  end

  defp maybe_put_completed_date_filter(filter, states) do
    if Enum.any?(states, &(&1 in @completed_types)),
      do: filter,
      else: Map.put(filter, "completedAt", %{"null" => true})
  end

  defp maybe_put_cancelled_date_filter(filter, states) do
    if Enum.any?(states, &(&1 in @cancelled_types)),
      do: filter,
      else: Map.put(filter, "canceledAt", %{"null" => true})
  end

  defp maybe_put_assignee_filter(filter, %{unassigned: true}) do
    Map.put(filter, "assignee", %{"null" => true})
  end

  defp maybe_put_assignee_filter(filter, %{mine: true}) do
    Map.put(filter, "assignee", %{"isMe" => %{"eq" => true}})
  end

  defp maybe_put_assignee_filter(filter, _args), do: filter

  defp maybe_put_team_filter(filter, %{team_key: key}) when is_binary(key) do
    Map.put(filter, "team", %{"key" => %{"eq" => key}})
  end

  defp maybe_put_team_filter(filter, _args), do: filter

  defp maybe_put_project_filter(filter, %{project_id: id}) when is_binary(id) do
    Map.put(filter, "project", %{"id" => %{"eq" => id}})
  end

  defp maybe_put_project_filter(filter, _args), do: filter

  defp maybe_put_state_filter(filter, %{state: [], status: []}), do: filter

  defp maybe_put_state_filter(filter, %{state: states, status: statuses}) do
    state_filter =
      %{}
      |> maybe_put_state_types(states)
      |> maybe_put_status_names(statuses)

    Map.put(filter, "state", state_filter)
  end

  defp maybe_put_state_types(filter, []), do: filter

  defp maybe_put_state_types(filter, states) do
    Map.put(filter, "type", %{"in" => states})
  end

  defp maybe_put_status_names(filter, []), do: filter

  defp maybe_put_status_names(filter, [status]) do
    Map.put(filter, "name", %{"eqIgnoreCase" => status})
  end

  defp maybe_put_status_names(filter, statuses) do
    names = Enum.map(statuses, &%{"name" => %{"eqIgnoreCase" => &1}})
    Map.put(filter, "or", names)
  end
end

defmodule LinearCli.Linear.Issue.Create do
  @moduledoc false
  use Ash.Resource.ManualCreate

  alias LinearCli.Api
  alias LinearCli.Linear.Issue

  # Ruby: Issue::ClassMethods#create - issueCreate mutation, returns the
  # created issue via Issue.base_fragment (not full_fragment - Ruby doesn't
  # refetch comments/full team detail for a just-created issue).
  def create(changeset, _opts, _context) do
    args = changeset.arguments

    input =
      %{"title" => args.title, "description" => args.description, "teamId" => args.team_id}
      |> maybe_put_label_ids(args.label_ids)
      |> maybe_put_project_id(Map.get(args, :project_id))

    case Api.call(document(), %{"input" => input}) do
      {:ok, %{"issueCreate" => %{"issue" => issue_map}}} when is_map(issue_map) ->
        {:ok, Issue.from_map(issue_map)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_label_ids(input, []), do: input
  defp maybe_put_label_ids(input, label_ids), do: Map.put(input, "labelIds", label_ids)

  defp maybe_put_project_id(input, nil), do: input
  defp maybe_put_project_id(input, project_id), do: Map.put(input, "projectId", project_id)

  # A function, not a module attribute: Issue.base_fields/0 reaches into
  # User (another file), so it must be evaluated at call time - see house
  # rule on cross-file compile-time module attribute evaluation order.
  defp document do
    "mutation($input: IssueCreateInput!) { issueCreate(input: $input) { issue { #{Issue.base_fields()} } } }"
  end
end

defmodule LinearCli.Linear.Issue.Update do
  @moduledoc false

  alias LinearCli.Api
  alias LinearCli.Linear.Issue

  # Ruby: Issue#update!(input) - the shared issueUpdate mutation that
  # assign!/attach_to_project!/close! all delegate to, refetching the
  # updated issue via Issue.full_fragment.
  def run(identifier, input) do
    case Api.call(document(), %{"id" => identifier, "input" => input}) do
      {:ok, %{"issueUpdate" => %{"issue" => issue_map}}} when is_map(issue_map) ->
        {:ok, Issue.from_map(issue_map)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A function, not a module attribute: Issue.full_fields/0 reaches into
  # User/Team/Comment (other files), so it must be evaluated at call time.
  defp document do
    "mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { issue { #{Issue.full_fields()} } } }"
  end
end

defmodule LinearCli.Linear.Issue.Update.Assign do
  @moduledoc false
  use Ash.Resource.ManualUpdate

  alias LinearCli.Linear.Issue

  def update(changeset, _opts, _context) do
    args = changeset.arguments
    state_id = Map.get(args, :state_id)

    input = %{"assigneeId" => args.assignee_id}
    input = if state_id, do: Map.put(input, "stateId", state_id), else: input

    Issue.Update.run(changeset.data.identifier, input)
  end
end

defmodule LinearCli.Linear.Issue.Update.AttachToProject do
  @moduledoc false
  use Ash.Resource.ManualUpdate

  alias LinearCli.Linear.Issue

  def update(changeset, _opts, _context) do
    Issue.Update.run(changeset.data.identifier, %{
      "projectId" => changeset.arguments.project_id
    })
  end
end

defmodule LinearCli.Linear.Issue.Update.Close do
  @moduledoc false
  use Ash.Resource.ManualUpdate

  alias LinearCli.Api
  alias LinearCli.Linear.Issue

  def update(changeset, _opts, _context) do
    args = changeset.arguments

    with {:ok, issue} <-
           Issue.Update.run(changeset.data.identifier, %{"stateId" => args.state_id}),
         :ok <- maybe_trash(changeset.data.id, args.trash) do
      {:ok, issue}
    end
  end

  defp maybe_trash(_id, false), do: :ok

  defp maybe_trash(id, true) do
    case Api.call(trash_document(), %{"id" => id}) do
      {:ok, %{"issueArchive" => %{"success" => true}}} -> :ok
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp trash_document do
    "mutation($id: String!) { issueArchive(id: $id, trash: true) { success } }"
  end
end

defmodule LinearCli.Linear.Issue.Update.SetStatus do
  @moduledoc false
  use Ash.Resource.ManualUpdate

  alias LinearCli.Linear.Issue

  def update(changeset, _opts, _context) do
    Issue.Update.run(changeset.data.identifier, %{
      "stateId" => changeset.arguments.state_id
    })
  end
end

defmodule LinearCli.Linear.Issue.Update.UpdateDescription do
  @moduledoc false
  use Ash.Resource.ManualUpdate

  alias LinearCli.Linear.Issue

  def update(changeset, _opts, _context) do
    Issue.Update.run(changeset.data.identifier, %{
      "description" => changeset.arguments.description
    })
  end
end
