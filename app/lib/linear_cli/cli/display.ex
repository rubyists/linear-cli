defmodule LinearCli.CLI.Display do
  @moduledoc """
  Formats domain resources for terminal output.

  Ported from `Rubyists::Linear::CLI::CommonOptions#display`
  (vendor/ruby-linear-cli/lib/linear/cli/common_options.rb) and each model's
  own `#to_s`/`#full`/`#display` methods.
  """

  alias LinearCli.CLI.Pager
  alias LinearCli.Linear.{Comment, Issue, IssueRelation, Project, ProjectUpdate, Team, User}
  alias LinearCli.Profiles.Profile

  @ash_internal_fields ~w(__meta__ __metadata__ __order__ __lateral_join_source__ aggregates calculations)a

  @doc """
  Prints `subject` (a resource, or a list of resources) per `opts[:output]`
  (`"text"`, the default, or `"json"`).

  Text output is routed through `$PAGER` (see `LinearCli.CLI.Pager`) when
  stdout is a terminal and the content exceeds the terminal height.
  `--output json` is never paged.
  """
  def show(subject, opts \\ %{}) do
    if Map.get(opts, :output, "text") == "json" do
      subject |> to_plain() |> Jason.encode!(pretty: true) |> IO.puts()
    else
      text = format_text(subject, opts)
      Pager.maybe_page(text, opts)
    end
  end

  @doc """
  Prints a dependency graph produced by `LinearCli.CLI.Commands.Issues.Graph.build/2`.

  With `--output json` emits only the structured graph object. Text output renders
  a diagram followed by Issues and Edges tables.
  """
  def show_graph(graph, opts \\ %{})

  def show_graph(graph, %{output: "json"}) do
    graph |> graph_to_plain() |> Jason.encode!(pretty: true) |> IO.puts()
  end

  def show_graph(graph, opts) do
    Pager.maybe_page(graph_text(graph), opts)
  end

  defp format_text([%IssueRelation{} | _] = relations, _opts), do: relations_block(relations)

  defp format_text(subject, opts) do
    subject |> List.wrap() |> Enum.map_join("\n", &format(&1, opts))
  end

  defp format(%IssueRelation{} = relation, _opts) do
    relation_line(relation)
  end

  defp format(%Team{} = team, _opts) do
    "#{String.pad_trailing(team.key || "", 6)} #{team.name}"
  end

  defp format(%Project{} = project, _opts) do
    "#{String.pad_trailing(project.name || "", 12)} #{project.url}"
  end

  defp format(%ProjectUpdate{} = update, _opts) do
    health = if update.health, do: " (#{update.health})", else: ""
    "Posted#{health}: #{update.url}"
  end

  # New in this port - Ruby has no equivalent (no bare `Comment` command
  # existed to display one). `LinearCli.CLI.Issue.Actions.issue_comment/2`/
  # `upsert_comment/4` already print a "Comment added to.../updated on..."
  # confirmation via `Prompt.ok/1` before this runs, so this only needs to
  # add the one thing that isn't in that line: a link to the comment.
  defp format(%Comment{} = comment, _opts) do
    comment.url || "(no URL returned)"
  end

  defp format(%Profile{} = profile, _opts) do
    marker = if profile.active, do: "* ", else: "  "

    "#{marker}#{String.pad_trailing(profile.name, 12)} team=#{profile.team || "-"} project=#{profile.project || "-"}"
  end

  defp format(%User{} = user, opts) do
    user_line(user, opts)
  end

  defp format(%Issue{} = issue, %{full: true}) do
    issue_full(issue)
  end

  defp format(%Issue{} = issue, opts) do
    issue_line(issue, opts)
  end

  defp user_line(user, opts) do
    basic = "#{String.pad_trailing(user.id || "", 20)}: #{user.name} <#{user.email}>"

    if Map.get(opts, :teams) && user.teams != [] do
      "#{basic} (#{Enum.map_join(user.teams, ", ", & &1.name)})"
    else
      basic
    end
  end

  defp issue_line(issue, opts \\ %{}) do
    state = if issue.state, do: "[#{issue.state.name}] ", else: ""
    basic = "#{String.pad_trailing(issue.identifier || "", 12)} #{state}#{issue.title}"
    line = if issue.assignee, do: "#{basic} (#{issue.assignee.name})", else: basic

    if Map.get(opts, :labels) && issue.labels != [] do
      "#{line} [#{Enum.map_join(issue.labels, ", ", & &1.name)}]"
    else
      line
    end
  end

  defp issue_full(issue) do
    header = issue_line(issue)
    sep = String.duplicate("-", String.length(header))
    labels = labels_line(issue.labels)
    description = render_markdown(issue.description)
    comments = Enum.map_join(issue.comments, "\n", &comment_block/1)

    all_relations =
      List.wrap(Map.get(issue, :relations, [])) ++
        List.wrap(Map.get(issue, :inverse_relations, []))

    relations_text = if all_relations != [], do: relations_block(all_relations), else: ""

    [header, sep, labels, description, comments, relations_text]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp labels_line([]), do: ""
  defp labels_line(labels), do: "Labels: #{Enum.map_join(labels, ", ", & &1.name)}"

  defp comment_block(comment) do
    user = (comment.user && comment.user.name) || "unknown"
    "--- #{user} ---\n#{render_markdown(comment.body)}"
  end

  defp render_markdown(nil), do: render_markdown("# No description for this issue")
  defp render_markdown(""), do: render_markdown("# No description for this issue")
  defp render_markdown(text), do: Marcli.render(text)

  @direction_labels %{
    blocks: {"Blocks", :outbound, "blocks"},
    blocked_by: {"Blocked by", :inbound, "blocks"},
    related: {"Related to", nil, "related"},
    duplicate: {"Duplicate of", nil, "duplicate"},
    similar: {"Similar to", nil, "similar"}
  }

  defp relations_block(relations) do
    grouped = Enum.group_by(relations, &relation_section_key/1)

    section_order = [:blocks, :blocked_by, :related, :duplicate, :similar]

    section_order
    |> Enum.flat_map(fn key ->
      case Map.get(grouped, key) do
        nil ->
          []

        rels ->
          {label, _dir, _type} = @direction_labels[key]
          lines = Enum.map(rels, &relation_line/1)
          ["#{label}:" | lines]
      end
    end)
    |> Enum.join("\n")
  end

  defp relation_section_key(%IssueRelation{direction: :outbound, type: "blocks"}), do: :blocks
  defp relation_section_key(%IssueRelation{direction: :inbound, type: "blocks"}), do: :blocked_by
  defp relation_section_key(%IssueRelation{type: "related"}), do: :related
  defp relation_section_key(%IssueRelation{type: "duplicate"}), do: :duplicate
  defp relation_section_key(%IssueRelation{type: "similar"}), do: :similar
  defp relation_section_key(%IssueRelation{}), do: :related

  defp relation_line(%IssueRelation{
         direction: direction,
         type: type,
         issue: src,
         related_issue: rel,
         id: id
       }) do
    other =
      case direction do
        :outbound -> rel
        :inbound -> src
      end

    identifier = (other && other.identifier) || "?"
    title = (other && other.title) || ""
    "  #{String.pad_trailing(identifier, 10)} #{title} [#{type}/#{id}]"
  end

  @doc "Returns a plain-map representation of an IssueRelation suitable for JSON encoding."
  def relation_to_plain(%IssueRelation{} = relation), do: to_plain(relation)

  # --- Dependency graph rendering ---

  defp graph_text(%{root: root, nodes: nodes, edges: edges}) do
    diagram = graph_diagram(root, nodes, edges)
    issues_table = graph_issues_table(root, nodes)
    edges_table = graph_edges_table(edges)

    [
      "Dependency graph",
      "A -> B means A blocks B",
      "",
      diagram,
      "",
      issues_table,
      "",
      edges_table
    ]
    |> Enum.join("\n")
  end

  defp graph_to_plain(%{root: root, nodes: nodes, edges: edges}) do
    %{
      "root" => root,
      "nodes" =>
        Enum.map(nodes, fn n ->
          %{"identifier" => n.identifier, "status" => n.status, "title" => n.title}
        end),
      "edges" => Enum.map(edges, fn e -> %{"source" => e.source, "target" => e.target} end)
    }
  end

  defp graph_diagram(root, nodes, edges) do
    by_id = Map.new(nodes, &{&1.identifier, &1})

    out_adj =
      Enum.reduce(edges, %{}, fn e, acc ->
        Map.update(acc, e.source, [e.target], &Enum.sort([e.target | &1]))
      end)

    in_adj =
      Enum.reduce(edges, %{}, fn e, acc ->
        Map.update(acc, e.target, [e.source], &Enum.sort([e.source | &1]))
      end)

    render_diagram(root, by_id, out_adj, in_adj)
  end

  defp node_label(%{identifier: id, status: s}) when is_binary(s) and s != "" do
    "#{id} [#{s}]"
  end

  defp node_label(%{identifier: id}), do: id

  # Renders a compact left-to-right diagram.
  # Predecessors of root appear on the left, root in the middle,
  # successors (and their successors) on the right.
  defp render_diagram(root, by_id, out_adj, in_adj) do
    root_node = Map.get(by_id, root, %{identifier: root, status: "", title: ""})
    root_label = node_label(root_node)

    pred_ids = Map.get(in_adj, root, [])
    succ_ids = Map.get(out_adj, root, [])

    pred_labels =
      Enum.map(pred_ids, fn id ->
        node_label(Map.get(by_id, id, %{identifier: id, status: ""}))
      end)

    succ_labels =
      Enum.map(succ_ids, fn id ->
        node_label(Map.get(by_id, id, %{identifier: id, status: ""}))
      end)

    # For each successor, gather their successors for chaining
    succ_succ_map =
      Map.new(succ_ids, fn id ->
        ids = Map.get(out_adj, id, [])

        labels =
          Enum.map(ids, fn sid ->
            node_label(Map.get(by_id, sid, %{identifier: sid, status: ""}))
          end)

        {id, labels}
      end)

    render_columns(pred_labels, root_label, succ_labels, succ_ids, succ_succ_map)
  end

  defp render_columns([], root_label, [], _succ_ids, _succ_succ_map) do
    root_label
  end

  defp render_columns([], root_label, [single_succ], succ_ids, succ_succ_map) do
    succ_id = List.first(succ_ids)
    ss_labels = Map.get(succ_succ_map, succ_id, [])
    chain_succ(root_label, single_succ, ss_labels)
  end

  defp render_columns([], root_label, succs, _succ_ids, _succ_succ_map) do
    first_line = "#{root_label} --+--> #{List.first(succs)}"
    pad = String.duplicate(" ", String.length(root_label) - 1)
    rest = Enum.map(Enum.drop(succs, 1), &"#{pad}    +--> #{&1}")
    Enum.join([first_line | rest], "\n")
  end

  defp render_columns(preds, root_label, succs, _succ_ids, _succ_succ_map) do
    pred_max = Enum.max(Enum.map(preds, &String.length/1))
    mid = div(length(preds), 2)

    preds
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {pl, i} ->
      padded = String.pad_trailing(pl, pred_max)
      if i == mid, do: mid_pred_line(padded, pred_max, root_label, succs), else: "#{padded} --+"
    end)
  end

  defp mid_pred_line(padded, _, root_label, []), do: "#{padded} --+--> #{root_label}"
  defp mid_pred_line(padded, _, root_label, [s]), do: "#{padded} --+--> #{root_label} --> #{s}"

  defp mid_pred_line(padded, pred_max, root_label, [h | t]) do
    first = "#{padded} --+--> #{root_label} --+--> #{h}"
    cont_pad = String.duplicate(" ", pred_max + String.length(root_label) + 11)
    Enum.join([first | Enum.map(t, &"#{cont_pad}+--> #{&1}")], "\n")
  end

  defp chain_succ(root_label, succ, []), do: "#{root_label} --> #{succ}"
  defp chain_succ(root_label, succ, [one]), do: "#{root_label} --> #{succ} --> #{one}"

  defp chain_succ(root_label, succ, [first | rest]) do
    pad = String.duplicate(" ", String.length(root_label) + String.length(succ) + 8)
    more = Enum.map(rest, &"#{pad}+--> #{&1}")
    Enum.join(["#{root_label} --> #{succ} --+--> #{first}" | more], "\n")
  end

  defp graph_issues_table(root, nodes) do
    id_w = nodes |> Enum.map(&String.length(&1.identifier)) |> Enum.max(fn -> 5 end) |> max(5)
    st_w = nodes |> Enum.map(&String.length(&1.status)) |> Enum.max(fn -> 6 end) |> max(6)

    header =
      "#{String.pad_trailing("ISSUE", id_w)}  #{String.pad_trailing("STATUS", st_w)}  TITLE"

    rows =
      Enum.map(nodes, fn n ->
        title = if n.identifier == root, do: "#{n.title} (root)", else: n.title

        "#{String.pad_trailing(n.identifier, id_w)}  #{String.pad_trailing(n.status, st_w)}  #{title}"
      end)

    Enum.join([header | rows], "\n")
  end

  defp graph_edges_table([]) do
    "SOURCE  TARGET\n(none)"
  end

  defp graph_edges_table(edges) do
    src_w = edges |> Enum.map(&String.length(&1.source)) |> Enum.max() |> max(6)
    header = "#{String.pad_trailing("SOURCE", src_w)}  TARGET"
    rows = Enum.map(edges, fn e -> "#{String.pad_trailing(e.source, src_w)}  #{e.target}" end)
    Enum.join([header | rows], "\n")
  end

  defp to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)

  defp to_plain(%_struct{} = record) do
    record
    |> Map.from_struct()
    |> Map.drop(@ash_internal_fields)
    |> Map.new(fn {k, v} -> {k, to_plain(v)} end)
  end

  defp to_plain(other), do: other
end
