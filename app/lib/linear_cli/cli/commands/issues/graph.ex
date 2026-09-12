defmodule LinearCli.CLI.Commands.Issues.Graph do
  @moduledoc """
  Builds a transitive dependency graph rooted at a single issue.

  Follows only `blocks` relations in both directions (outbound = this issue
  blocks others; inbound = others block this issue). Traversal is BFS,
  visiting each issue identifier at most once, so cycles and shared
  dependencies terminate safely.

  Returns a plain map ready for display or JSON encoding:

      %{
        root: "EXT-56",
        nodes: [%{identifier: "EXT-56", status: "In Progress", title: "..."}, ...],
        edges: [%{source: "EXT-40", target: "EXT-56"}, ...]
      }

  `nodes` is sorted by identifier; `edges` by (source, target).
  """

  alias LinearCli.Linear

  @max_nodes 100

  @doc """
  Builds the transitive dependency graph rooted at `root_identifier`.

  `root_issue` is the already-fetched `%LinearCli.Linear.Issue{}` for the root,
  used to populate the root node's title and status without an extra API call.

  Returns `{:ok, graph}` or `{:error, {issue_id, reason}}` where the
  error identifies which issue's relations could not be fetched.
  """
  @spec build(String.t(), struct()) ::
          {:ok, %{root: String.t(), nodes: list(map()), edges: list(map())}}
          | {:error, {String.t(), term()}}
  def build(root_identifier, root_issue) do
    root_status = (root_issue.state && root_issue.state.name) || ""
    root_title = root_issue.title || ""

    initial_nodes = %{
      root_identifier => %{
        identifier: root_identifier,
        status: root_status,
        title: root_title
      }
    }

    case bfs([root_identifier], MapSet.new(), initial_nodes, []) do
      {:ok, nodes_map, edges} ->
        sorted_nodes =
          nodes_map
          |> Map.values()
          |> Enum.sort_by(& &1.identifier)

        sorted_edges =
          edges
          |> Enum.uniq_by(fn %{source: s, target: t} -> {s, t} end)
          |> Enum.sort_by(fn %{source: s, target: t} -> {s, t} end)

        {:ok, %{root: root_identifier, nodes: sorted_nodes, edges: sorted_edges}}

      {:error, _} = err ->
        err
    end
  end

  # BFS: queue is a list of identifiers to visit; visited is a MapSet of
  # identifiers already processed; nodes_map maps identifier -> node info;
  # edges is an accumulator list.
  defp bfs([], _visited, nodes_map, edges), do: {:ok, nodes_map, edges}

  defp bfs([id | rest], visited, nodes_map, edges) do
    if MapSet.member?(visited, id) or map_size(nodes_map) >= @max_nodes do
      bfs(rest, visited, nodes_map, edges)
    else
      visited = MapSet.put(visited, id)

      case Linear.issue_relations(id) do
        {:error, reason} ->
          {:error, {id, reason}}

        {:ok, relations} ->
          blocks_only = Enum.filter(relations, &(&1.type == "blocks"))

          {new_nodes_map, new_edges, new_queue} =
            Enum.reduce(blocks_only, {nodes_map, edges, rest}, fn rel, acc ->
              process_relation(rel, acc, visited)
            end)

          bfs(new_queue, visited, new_nodes_map, new_edges)
      end
    end
  end

  defp process_relation(rel, {nm, ed, q}, visited) do
    {nm, ed, q} = add_endpoint(rel.issue, nm, ed, q, visited)
    {nm, ed, q} = add_endpoint(rel.related_issue, nm, ed, q, visited)
    source = rel.issue && rel.issue.identifier
    target = rel.related_issue && rel.related_issue.identifier
    ed = if source && target, do: [%{source: source, target: target} | ed], else: ed
    {nm, ed, q}
  end

  defp add_endpoint(nil, nodes_map, edges, queue, _visited), do: {nodes_map, edges, queue}

  defp add_endpoint(endpoint, nodes_map, edges, queue, visited) do
    id = endpoint.identifier

    nodes_map =
      Map.put_new(nodes_map, id, %{
        identifier: id,
        status: get_in(endpoint, [:state, :name]) || "",
        title: endpoint.title || ""
      })

    queue =
      if MapSet.member?(visited, id) or id in queue,
        do: queue,
        else: queue ++ [id]

    {nodes_map, edges, queue}
  end
end
