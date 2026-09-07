defmodule LinearCli.Linear.IssueRelation do
  @moduledoc """
  A directional relation between two Linear issues (blocks, blocked-by, related,
  duplicate, similar).

  No data layer — all actions call `LinearCli.Api` directly.  `direction`
  records whether this relation appeared in `Issue.relations` (`:outbound`) or
  `Issue.inverseRelations` (`:inbound`), allowing the display layer to render
  "Blocks" vs "Blocked by" without the caller having to reconstruct direction
  from endpoint order.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    read :list do
      argument :issue_id, :string, allow_nil?: false
      manual LinearCli.Linear.IssueRelation.Read.List
    end

    create :create do
      argument :issue_id, :string, allow_nil?: false
      argument :related_issue_id, :string, allow_nil?: false
      argument :type, :string, allow_nil?: false
      manual LinearCli.Linear.IssueRelation.Create
    end

    destroy :destroy do
      manual LinearCli.Linear.IssueRelation.Destroy
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :type, :string, public?: true
    attribute :direction, :atom, public?: true
    attribute :issue, :term, public?: true
    attribute :related_issue, :term, public?: true
  end

  @endpoint_fields "id identifier title url"

  @doc "GraphQL field selection for each issue endpoint inside a relation node."
  def endpoint_fields, do: @endpoint_fields

  @doc "GraphQL field selection for a full relation node."
  def relation_fields do
    "id type " <>
      "issue { #{endpoint_fields()} } " <>
      "relatedIssue { #{endpoint_fields()} }"
  end

  @doc false
  def from_map(map, direction) when is_atom(direction) do
    struct!(__MODULE__,
      id: map["id"],
      type: map["type"],
      direction: direction,
      issue: endpoint_from_map(map["issue"]),
      related_issue: endpoint_from_map(map["relatedIssue"])
    )
  end

  defp endpoint_from_map(nil), do: nil

  defp endpoint_from_map(map) do
    %{id: map["id"], identifier: map["identifier"], title: map["title"], url: map["url"]}
  end
end

defmodule LinearCli.Linear.IssueRelation.Create do
  @moduledoc false
  use Ash.Resource.ManualCreate

  alias LinearCli.Api
  alias LinearCli.Linear.IssueRelation

  def create(changeset, _opts, _context) do
    args = changeset.arguments

    case Api.call(document(), %{
           "issueId" => args.issue_id,
           "relatedIssueId" => args.related_issue_id,
           "type" => args.type
         }) do
      {:ok, %{"issueRelationCreate" => %{"issueRelation" => rel_map}}} when is_map(rel_map) ->
        {:ok, IssueRelation.from_map(rel_map, :outbound)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, {:graphql_errors, [%{"message" => message} | _] = errors}} ->
        if duplicate_error?(message) do
          {:error, {:duplicate_relation, message}}
        else
          {:error, {:graphql_errors, errors}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp duplicate_error?(message) do
    message = String.downcase(message)
    String.contains?(message, "already exists") or String.contains?(message, "duplicate")
  end

  defp document do
    "mutation($issueId: String!, $relatedIssueId: String!, $type: IssueRelationType!) { issueRelationCreate(input: { issueId: $issueId, relatedIssueId: $relatedIssueId, type: $type }) { issueRelation { #{IssueRelation.relation_fields()} } success } }"
  end
end

defmodule LinearCli.Linear.IssueRelation.Destroy do
  @moduledoc false
  use Ash.Resource.ManualDestroy

  alias LinearCli.Api

  def destroy(changeset, _opts, _context) do
    relation_id = changeset.data.id

    case Api.call(document(), %{"id" => relation_id}) do
      {:ok, %{"issueRelationDelete" => %{"success" => true}}} ->
        {:ok, changeset.data}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp document do
    "mutation($id: String!) { issueRelationDelete(id: $id) { success entityId } }"
  end
end

defmodule LinearCli.Linear.IssueRelation.Read.List do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias LinearCli.Api
  alias LinearCli.Linear.IssueRelation

  # Fetches both outbound (`relations`) and inbound (`inverseRelations`)
  # concurrently, paginating each independently up to 100 records per direction.
  def read(query, _ecto_query, _opts, _context) do
    issue_id = query.arguments.issue_id

    [outbound_task, inbound_task] = [
      Task.async(fn -> fetch_all(issue_id, "relations", :outbound) end),
      Task.async(fn -> fetch_all(issue_id, "inverseRelations", :inbound) end)
    ]

    [outbound_result, inbound_result] = Task.await_many([outbound_task, inbound_task], 30_000)

    with {:ok, outbound} <- outbound_result,
         {:ok, inbound} <- inbound_result do
      {:ok, outbound ++ inbound}
    end
  end

  defp fetch_all(issue_id, connection_field, direction) do
    fetch_page(issue_id, connection_field, direction, nil, [])
  end

  defp fetch_page(issue_id, connection_field, direction, after_cursor, acc) do
    vars = %{"issueId" => issue_id, "first" => 50, "after" => after_cursor}

    case Api.call(document(connection_field), vars) do
      {:ok, %{"issue" => nil}} ->
        {:error, {:not_found, issue_id}}

      {:ok, data} ->
        case get_in(data, ["issue", connection_field]) do
          %{"edges" => edges, "pageInfo" => page_info} ->
            decoded = Enum.map(edges, &IssueRelation.from_map(&1["node"], direction))
            acc = acc ++ decoded

            if page_info["hasNextPage"] and length(acc) < 100 do
              fetch_page(issue_id, connection_field, direction, page_info["endCursor"], acc)
            else
              {:ok, acc}
            end

          other ->
            {:error, {:unexpected_response, other}}
        end

      {:error, {:http_error, status, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A function, not a module attribute: IssueRelation.relation_fields/0 is a
  # cross-module call; evaluated at call time so compile-time ordering doesn't
  # matter.
  defp document(connection_field) do
    """
    query($issueId: String!, $first: Int!, $after: String) {
      issue(id: $issueId) {
        #{connection_field}(first: $first, after: $after) {
          edges { node { #{IssueRelation.relation_fields()} } cursor }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """
  end
end
