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
      manual LinearCli.Linear.Issue.Read.List
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :identifier, :string, public?: true
    attribute :title, :string, public?: true
    attribute :branch_name, :string, public?: true
    attribute :description, :string, public?: true
    attribute :assignee, :term, public?: true
    attribute :team, :term, public?: true
    attribute :comments, {:array, :term}, public?: true, default: []
  end

  @issue_fields "id identifier title branchName description createdAt updatedAt"

  @doc "GraphQL field selection for an issue plus its assignee/team (Ruby: Issue.base_fragment)."
  def base_fields do
    "#{@issue_fields} " <>
      "assignee { #{LinearCli.Linear.User.fields_with_teams()} } " <>
      "team { #{LinearCli.Linear.Team.base_fields()} }"
  end

  @doc "GraphQL field selection for a fully detailed issue, incl. comments (Ruby: Issue.full_fragment)."
  def full_fields do
    "#{@issue_fields} " <>
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

  defp find_by_ids(ids) do
    result =
      Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
        case Api.call(find_document(), %{"id" => String.upcase(id)}) do
          {:ok, %{"issue" => issue_map}} when is_map(issue_map) ->
            {:cont, {:ok, [Issue.from_map(issue_map) | acc]}}

          {:ok, %{"issue" => nil}} ->
            {:halt, {:error, {:not_found, id}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    with {:ok, issues} <- result do
      {:ok, Enum.reverse(issues)}
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
  defp build_filter(args) do
    %{"completedAt" => %{"null" => true}, "canceledAt" => %{"null" => true}}
    |> maybe_put_assignee_filter(args)
    |> maybe_put_team_filter(args)
    |> maybe_put_project_filter(args)
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
end
