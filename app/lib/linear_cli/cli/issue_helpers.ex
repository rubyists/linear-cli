defmodule LinearCli.CLI.IssueHelpers do
  @moduledoc """
  Shared issue-command helpers - open a PR, create, self-assign.

  Ported from `Rubyists::Linear::CLI::Issue`
  (vendor/ruby-linear-cli/lib/linear/commands/issue.rb): `create_pr!`,
  `issue_pr`, `make_da_issue!`, `gimme_da_issue!`.

  Lifecycle mutations (comment, close/cancel, description update, project
  attachment/move, and update-dispatch) have been extracted to
  `LinearCli.CLI.Issue.Actions`. Bare-ID expansion lives in
  `LinearCli.CLI.Issue.Identifiers`. Workflow-state selection lives in
  `LinearCli.CLI.Issue.WorkflowStates`.

  ## Return convention

  Every function here returns `{:ok, result}` or `{:error, reason}` (never
  raises).

  `reason` is either whatever `LinearCli.Api`/an Ash manual action already
  surfaces (a transport/GraphQL/validation error - a genuine system
  failure), or a tagged tuple for "the user gave us something we can't act
  on, tell them clearly" cases, mirroring Ruby's `SmellsBad` exception:

      {:error, {:smells_bad, message}}

  where `message` is a human-readable `String.t()`.

  ## Project lookups

  `make_da_issue!/1` (Ruby: `team.projects`) needs a team's projects. Neither
  `LinearCli.Linear.Issue` nor `LinearCli.Linear.Team` stores a `:projects`
  field on their structs (Team's own GraphQL `full_fields/0` embeds a
  `projects` sub-selection, but `Team.from_map/1` never parses it into an
  attribute - there's nowhere on the struct to put it), so it calls
  `LinearCli.Linear.projects_by_team/1` domain interface instead.

  ## `create_pr!/3`

  Ported from `CLI::Issue#create_pr!`, which shells out to `gh pr create`.
  Ruby branches on whether `body` is a `Tempfile` (`--body-file`) or a
  plain `String` (`--body`); this port's `body` is always a `String.t()`
  (see `LinearCli.CLI.WhatFor.pr_description_for/2`'s own moduledoc note on
  why it never returns a Ruby-style `Tempfile` handle here), so only the
  `--body` shape applies. Takes an injectable `runner` (a `(title, body) ->
  String.t()` function), defaulting to a real `System.cmd/3` call, so tests
  never actually shell out to a real `gh` - the same pattern this codebase
  already uses for `LinearCli.CLI.main/2`'s injectable `halt` and
  `LinearCli.Git`'s injectable `cwd:`.
  """

  alias LinearCli.CLI.Issue.{Identifiers, WorkflowStates}
  alias LinearCli.CLI.{Projects, Prompt, WhatFor}
  alias LinearCli.{Linear, Profiles}

  @doc """
  Shells out to `gh pr create -a @me --title TITLE --body BODY`, returning
  whatever the command printed to stdout (Ruby's backtick-captured output -
  typically the created PR's URL).

  `runner`, a `(title, body) -> String.t()` function, defaults to a real
  `System.cmd/3` call - pass an override in tests. Ported from
  `CLI::Issue#create_pr!`; see this module's moduledoc for why only the
  `--body` (never `--body-file`) shape applies here.
  """
  @spec create_pr!(String.t(), String.t(), (String.t(), String.t() -> String.t())) :: String.t()
  def create_pr!(title, body, runner \\ &default_gh_runner/2)
  def create_pr!(title, body, runner), do: runner.(title, body)

  defp default_gh_runner(title, body) do
    {output, _exit_status} =
      System.cmd(
        "gh",
        ["pr", "create", "-a", "@me", "--title", title, "--body", body],
        stderr_to_stdout: true
      )

    output
  end

  @doc """
  Opens a PR for `issue`: resolves a title/description (asking, via
  `LinearCli.CLI.WhatFor.pr_title_for/1`/`pr_description_for/2`, if not
  already given in `opts`), then runs `create_pr!/3` and prints its output.

  `opts`: `:title`, `:description` (Ruby's implicit `options[:title]`/
  `options[:description]` - note Ruby's own `update_issue` never actually
  passes either through, always calling `issue_pr(issue)` bare, so both are
  ported for signature fidelity but are effectively always prompted for in
  practice); `:runner`, this port's addition, forwarded to `create_pr!/3`.

  Ported from `CLI::Issue#issue_pr`. Always returns `:ok`.
  """
  @spec issue_pr(%Linear.Issue{}, keyword()) :: :ok
  def issue_pr(issue, opts \\ []) do
    title = opts[:title] || WhatFor.pr_title_for(issue)
    body = opts[:description] || WhatFor.pr_description_for(issue)
    runner = Keyword.get(opts, :runner, &default_gh_runner/2)

    Prompt.warn(create_pr!(title, body, runner))
    :ok
  end

  @doc """
  Creates a new issue, resolving every field that wasn't already given in
  `opts` interactively (title, description, team, labels, project - via
  `LinearCli.CLI.WhatFor`/`LinearCli.CLI.Projects`).

  `opts` (Ruby's `**options`): `:title`, `:description`, `:team`, `:labels`,
  `:project`. `:team`/`:project`, if omitted, fall back to
  `LinearCli.Profiles.default_team/0`/`default_project/0` (the active
  profile, if any) before `WhatFor.team_for/1`/`Projects.project_for/2`'s
  own interactive prompting kicks in.

  Ported from `CLI::Issue#make_da_issue!`.
  """
  @spec make_da_issue!(keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def make_da_issue!(opts \\ []) do
    if opts[:yes], do: make_da_issue_no_prompts!(opts), else: make_da_issue_interactive!(opts)
  end

  defp make_da_issue_interactive!(opts) do
    title = WhatFor.title_for(opts[:title])
    description = WhatFor.description_for(opts[:description])
    team = WhatFor.team_for(opts[:team] || Profiles.default_team())
    labels = WhatFor.labels_for(team, opts[:labels])
    project_search = opts[:project] || Profiles.default_project()

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: project_search}) do
      project = Projects.project_for(projects, project_search)
      label_ids = Enum.map(labels, & &1.id)
      params = maybe_put_project_id(%{label_ids: label_ids}, project)

      Linear.create_issue(title, description, team.id, params)
    end
  end

  defp make_da_issue_no_prompts!(opts) do
    with {:ok, title} <- require_field(opts[:title], "--title"),
         {:ok, description} <- require_field(opts[:description], "--description"),
         {:ok, team} <- resolve_team_strict(opts[:team] || Profiles.default_team()) do
      labels =
        case opts[:labels] do
          nil -> []
          [] -> []
          labels -> WhatFor.labels_for(team, labels)
        end

      project_search = opts[:project] || Profiles.default_project()

      with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: project_search}) do
        project =
          if project_search,
            do: Projects.project_for_strict(projects, project_search),
            else: nil

        label_ids = Enum.map(labels, & &1.id)
        params = maybe_put_project_id(%{label_ids: label_ids}, project)
        Linear.create_issue(title, description, team.id, params)
      end
    end
  end

  defp require_field(nil, flag),
    do: {:error, {:smells_bad, "#{flag} is required with --yes"}}

  defp require_field(value, _flag), do: {:ok, value}

  defp resolve_team_strict(nil) do
    case Linear.my_teams() do
      {:ok, [team]} ->
        {:ok, team}

      {:ok, []} ->
        {:error, {:smells_bad, "--team is required (you belong to no teams)"}}

      {:ok, _teams} ->
        {:error, {:smells_bad, "--team is required when you belong to multiple teams"}}

      {:error, reason} ->
        {:error, {:smells_bad, "Could not fetch teams: #{inspect(reason)}"}}
    end
  end

  defp resolve_team_strict(key) do
    case Linear.find_team(key) do
      {:ok, team} -> {:ok, team}
      {:error, _reason} -> {:error, {:smells_bad, "--team #{inspect(key)} not found"}}
    end
  end

  defp maybe_put_project_id(params, nil), do: params
  defp maybe_put_project_id(params, project), do: Map.put(params, :project_id, project.id)

  @doc """
  Looks up `issue_id` and self-assigns it to the caller, unless it's already
  assigned to them.

  `opts[:me]` overrides the caller lookup (this port's stand-in for Ruby's
  `me: Rubyists::Linear::User.me` keyword default) - real callers omit it
  and get `LinearCli.Linear.me/0`; tests pass it to avoid stubbing the
  `viewer` query too.

  Ported from `CLI::Issue#gimme_da_issue!`.
  """
  @spec gimme_da_issue!(String.t(), keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def gimme_da_issue!(issue_id, opts \\ []) do
    issue_id = Identifiers.expand_issue_id(issue_id)
    status_opt = parse_status_opt(opts)

    with {:ok, me} <- resolve_me(opts),
         {:ok, [issue]} <- Linear.issues(%{ids: [issue_id]}),
         {:ok, state_id} <- resolve_status_for_issue(issue, status_opt) do
      assign_or_confirm(issue, me, issue_id, state_id)
    end
  end

  defp parse_status_opt(opts) do
    case Keyword.fetch(opts, :state_id) do
      {:ok, id} -> {:resolved, id}
      :error -> {:name, Keyword.get(opts, :status)}
    end
  end

  defp resolve_status_for_issue(_issue, {:resolved, id}), do: {:ok, id}
  defp resolve_status_for_issue(_issue, {:name, nil}), do: {:ok, nil}

  defp resolve_status_for_issue(issue, {:name, name}) do
    with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id) do
      case WorkflowStates.resolve_workflow_state(states, name) do
        {:ok, state} -> {:ok, state.id}
        error -> error
      end
    end
  end

  defp assign_or_confirm(%{assignee: %{id: id}} = issue, %{id: id}, issue_id, nil) do
    Prompt.say("You are already assigned #{issue_id}")
    {:ok, issue}
  end

  defp assign_or_confirm(issue, me, issue_id, state_id) do
    Prompt.say("Assigning issue #{issue_id} to ya")
    Linear.assign_issue(issue, me.id, %{state_id: state_id})
  end

  defp resolve_me(opts) do
    case Keyword.fetch(opts, :me) do
      {:ok, me} -> {:ok, me}
      :error -> Linear.me()
    end
  end
end
