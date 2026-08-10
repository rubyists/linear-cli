defmodule LinearCli.CLI.Display do
  @moduledoc """
  Formats domain resources for terminal output.

  Ported from `Rubyists::Linear::CLI::CommonOptions#display`
  (vendor/ruby-linear-cli/lib/linear/cli/common_options.rb) and each model's
  own `#to_s`/`#full`/`#display` methods.
  """

  alias LinearCli.Linear.{Issue, Project, ProjectUpdate, Team, User}
  alias LinearCli.Profiles.Profile

  @ash_internal_fields ~w(__meta__ __metadata__ __order__ __lateral_join_source__ aggregates calculations)a

  @doc """
  Prints `subject` (a resource, or a list of resources) per `opts[:output]`
  (`"text"`, the default, or `"json"`).
  """
  def show(subject, opts \\ %{}) do
    if Map.get(opts, :output, "text") == "json" do
      subject |> to_plain() |> Jason.encode!(pretty: true) |> IO.puts()
    else
      subject |> List.wrap() |> Enum.each(&puts_text(&1, opts))
    end
  end

  defp puts_text(%Team{} = team, _opts) do
    IO.puts("#{String.pad_trailing(team.key || "", 6)} #{team.name}")
  end

  defp puts_text(%Project{} = project, _opts) do
    IO.puts("#{String.pad_trailing(project.name || "", 12)} #{project.url}")
  end

  defp puts_text(%ProjectUpdate{} = update, _opts) do
    health = if update.health, do: " (#{update.health})", else: ""
    IO.puts("Posted#{health}: #{update.url}")
  end

  defp puts_text(%Profile{} = profile, _opts) do
    marker = if profile.active, do: "* ", else: "  "

    IO.puts(
      "#{marker}#{String.pad_trailing(profile.name, 12)} team=#{profile.team || "-"} project=#{profile.project || "-"}"
    )
  end

  defp puts_text(%User{} = user, opts) do
    IO.puts(user_line(user, opts))
  end

  defp puts_text(%Issue{} = issue, %{full: true}) do
    IO.puts(issue_full(issue))
  end

  defp puts_text(%Issue{} = issue, _opts) do
    IO.puts(issue_line(issue))
  end

  defp user_line(user, opts) do
    basic = "#{String.pad_trailing(user.id || "", 20)}: #{user.name} <#{user.email}>"

    if Map.get(opts, :teams) && user.teams != [] do
      "#{basic} (#{Enum.map_join(user.teams, ", ", & &1.name)})"
    else
      basic
    end
  end

  defp issue_line(issue) do
    basic = "#{String.pad_trailing(issue.identifier || "", 12)} #{issue.title}"
    if issue.assignee, do: "#{basic} (#{issue.assignee.name})", else: basic
  end

  defp issue_full(issue) do
    header = issue_line(issue)
    sep = String.duplicate("-", String.length(header))
    description = render_markdown(issue.description)
    comments = Enum.map_join(issue.comments, "\n", &comment_block/1)

    Enum.join([header, sep, description, comments], "\n")
  end

  defp comment_block(comment) do
    user = (comment.user && comment.user.name) || "unknown"
    "--- #{user} ---\n#{render_markdown(comment.body)}"
  end

  defp render_markdown(nil), do: render_markdown("# No description for this issue")
  defp render_markdown(""), do: render_markdown("# No description for this issue")
  defp render_markdown(text), do: Marcli.render(text)

  defp to_plain(list) when is_list(list), do: Enum.map(list, &to_plain/1)

  defp to_plain(%_struct{} = record) do
    record
    |> Map.from_struct()
    |> Map.drop(@ash_internal_fields)
    |> Map.new(fn {k, v} -> {k, to_plain(v)} end)
  end

  defp to_plain(other), do: other
end
