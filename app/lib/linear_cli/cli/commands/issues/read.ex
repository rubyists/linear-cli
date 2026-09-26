defmodule LinearCli.CLI.Commands.Issues.Read do
  @moduledoc """
  Issue read commands: list and view.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/list.rb and
  commands/issue/view.rb.
  """

  alias LinearCli.Browser
  alias LinearCli.CLI.Commands.Issues.Filter
  alias LinearCli.CLI.Commands.Issues.Graph
  alias LinearCli.CLI.Display
  alias LinearCli.CLI.Issue.Identifiers
  alias LinearCli.Linear

  @doc """
  Ported from commands/issue/list.rb + operations/issue/list.rb.

  `--project`/`-p` resolution is team-scoped when `--team` is given (or
  the active profile supplies a team) - it searches that team's projects via
  `projects_by_team`. Without a team context it falls back to all workspace
  projects (`Project.all`). Prompts interactively when the search is
  ambiguous or omitted-but-requested (`-p -`). Only resolved at all when
  `--project` was actually given (or `LinearCli.Profiles.default_project/0`
  supplies one) - unlike `issue create`/`issue update`, a bare `issue list`
  with no active profile applies no project filter and never prompts.
  `--team`/`--project` passed explicitly always win over the active profile.
  """
  def issue_list(%{flags: flags, options: options, unknown: ids}) do
    with {:ok, input} <-
           Filter.build_input(flags, options, Enum.map(ids, &Identifiers.expand_issue_id/1)) do
      with {:ok, issues} <- Linear.issues(input) do
        Display.show(issues, %{
          output: options.output,
          full: flags.full,
          labels: input.include_labels
        })

        :ok
      end
    end
  end

  @doc """
  Shows full details for a single issue - equivalent to `issue list --full ISSUE_ID`.

  Mirrors `gh issue view`: a dedicated verb for the single-issue display case,
  making it discoverable without knowing about `list`'s `--full` flag.

  With `-w`/`--web`, opens the issue URL in the default browser instead of
  printing it. The `opts` keyword arg accepts an injectable `opener` for tests.
  """
  @spec issue_view(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_view(result, opts \\ [])

  def issue_view(%{args: %{issue_id: issue_id}, flags: flags, options: options}, opts) do
    graph? = Map.get(flags, :graph, false)
    web? = flags.web

    cond do
      graph? && web? ->
        {:error, {:smells_bad, "--graph and --web cannot be used together"}}

      graph? ->
        expanded_id = Identifiers.expand_issue_id(issue_id)

        with {:ok, [issue]} <- Linear.issues(%{ids: [expanded_id]}),
             {:ok, graph} <- Graph.build(issue.identifier, issue) do
          Display.show_graph(graph, %{output: options.output})
          :ok
        end

      true ->
        expanded_id = Identifiers.expand_issue_id(issue_id)

        with {:ok, [issue]} <- Linear.issues(%{ids: [expanded_id]}) do
          if web? do
            Browser.open_url(issue.url, opts)
          else
            Display.show(issue, %{output: options.output, full: true})
            :ok
          end
        end
    end
  end
end
