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
  # existed to display one). `LinearCli.CLI.IssueHelpers.issue_comment/2`/
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

  defp to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)

  defp to_plain(%_struct{} = record) do
    record
    |> Map.from_struct()
    |> Map.drop(@ash_internal_fields)
    |> Map.new(fn {k, v} -> {k, to_plain(v)} end)
  end

  defp to_plain(other), do: other
end
