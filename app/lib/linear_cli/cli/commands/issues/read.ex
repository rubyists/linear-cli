defmodule LinearCli.CLI.Commands.Issues.Read do
  @moduledoc """
  Issue read commands: list and view.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/list.rb and
  commands/issue/view.rb.
  """

  alias LinearCli.Browser
  alias LinearCli.CLI.{Display, Projects}
  alias LinearCli.CLI.Issue.Identifiers
  alias LinearCli.{Linear, Profiles}

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
    no_profile = Map.get(flags, :no_profile, false)
    team_key = options.team || unless no_profile, do: Profiles.default_team()

    project_source =
      options.project || unless no_profile, do: Profiles.default_project()

    with {:ok, project_id} <- resolve_project_id(project_source, team_key) do
      label_filter = Map.get(options, :labels) || []
      include_labels = Map.get(flags, :include_labels, false) || label_filter != []

      input = %{
        ids: Enum.map(ids, &Identifiers.expand_issue_id/1),
        mine: !flags.no_mine,
        unassigned: flags.unassigned,
        team_key: team_key,
        project_id: project_id,
        all: Map.get(flags, :all, false),
        state: Map.get(options, :state) || [],
        status: Map.get(options, :status) || [],
        labels: label_filter,
        include_labels: include_labels
      }

      with {:ok, issues} <- Linear.issues(input) do
        Display.show(issues, %{
          output: options.output,
          full: flags.full,
          labels: include_labels
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
    expanded_id = Identifiers.expand_issue_id(issue_id)

    with {:ok, [issue]} <- Linear.issues(%{ids: [expanded_id]}) do
      if flags.web do
        Browser.open_url(issue.url, opts)
      else
        Display.show(issue, %{output: options.output, full: true})
        :ok
      end
    end
  end

  defp resolve_project_id(nil, _team_key), do: {:ok, nil}

  defp resolve_project_id(search, team_key) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key),
         {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}) do
      case Projects.project_for(projects, search) do
        nil -> {:ok, nil}
        project -> {:ok, project.id}
      end
    end
  end

  defp resolve_project_id(search, _team_key) do
    with {:ok, projects} <- Linear.projects() do
      case Projects.project_for(projects, search) do
        nil -> {:ok, nil}
        project -> {:ok, project.id}
      end
    end
  end
end
