defmodule LinearCli.CLI.IssueHelpers do
  @moduledoc """
  Shared issue-command helpers - comment, close, cancel, open a PR, attach a
  project, dispatch an update, create, self-assign.

  Ported from `Rubyists::Linear::CLI::Issue`
  (vendor/ruby-linear-cli/lib/linear/commands/issue.rb): `issue_comment`,
  `cancel_issue`, `close_issue`, `create_pr!`, `issue_pr`, `attach_project`,
  `update_issue`, `make_da_issue!`, `gimme_da_issue!`.

  ## Return convention

  Every function here returns `{:ok, result}` or `{:error, reason}` (never
  raises), *except* `update_issue/2`, which normalizes down to
  `:ok | {:error, reason}` to match this codebase's CLI dispatch contract
  (`LinearCli.CLI.run/3`, which expects exactly that shape from a command
  handler) - it's the one function here a later phase is likely to wire
  directly to a subcommand.

  `reason` is either whatever `LinearCli.Api`/an Ash manual action already
  surfaces (a transport/GraphQL/validation error - a genuine system
  failure), or a new tagged tuple this module introduces for "the user gave
  us something we can't act on, tell them clearly" cases, mirroring Ruby's
  `SmellsBad` exception (`vendor/ruby-linear-cli/lib/linear/exceptions.rb`,
  raised e.g. by `CLI::SubCommands#ask_for_team` when no team is found):

      {:error, {:smells_bad, message}}

  where `message` is a human-readable `String.t()`. The one case this module
  itself raises it: `cancelled_state_for/1`/`completed_state_for/1` finding
  *zero* matching workflow states for an issue's team (Ruby's own
  `cancelled_states.first`/`completed_states.first` would silently return
  `nil` there and blow up two calls later inside `close!`'s GraphQL
  round-trip instead - this port catches it at the source with a clear
  message). A later phase wiring this into `LinearCli.CLI.main/2`'s
  dispatch can add a `handle_error` clause matching `{:smells_bad, message}`
  and print `message` + `halt.(22)`, mirroring Ruby's `CLI::Caller#call`
  `rescue SmellsBad` clause (which maps to exit code 22).

  ## `cancelled_state_for/1` / `completed_state_for/1`

  Ruby has these on `BaseModel` (`#cancelled_states`/`#completed_states`,
  filtering `issue.workflow_states`, itself `team.workflow_states`) plus
  `CLI::WhatFor#cancelled_state_for`/`#completed_state_for` (the
  first-if-only-one-else-prompt logic `close_issue`/`cancel_issue` call).
  Neither made it into this port's `LinearCli.CLI.WhatFor`
  (`app/lib/linear_cli/cli/what_for.ex`) or anywhere else yet, so both
  layers are combined and added here as public functions - the only
  reasonable place, since `close_issue/2`/`cancel_issue/2` (this module)
  are their only callers.

  ## Project lookups

  `attach_project/2` (Ruby: `issue.team.projects`) and `make_da_issue!/1`
  (Ruby: `team.projects`) both need a team's projects. Neither
  `LinearCli.Linear.Issue` nor `LinearCli.Linear.Team` stores a `:projects`
  field on their structs (Team's own GraphQL `full_fields/0` embeds a
  `projects` sub-selection, but `Team.from_map/1` never parses it into an
  attribute - there's nowhere on the struct to put it), so both call the new
  `LinearCli.Linear.projects_by_team/1` domain interface instead (added
  alongside this module, wrapping the pre-existing
  `LinearCli.Linear.Project` `:by_team` action the same way
  `labels_by_team/1`/`workflow_states_by_team/1` already wrap their own
  `:by_team` actions).

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

  alias LinearCli.CLI.{Projects, Prompt, WhatFor}
  alias LinearCli.{Favorites, Linear, Profiles}

  # A "bare" issue id is just digits - anything with a `-` (an already
  # team-prefixed identifier, e.g. "CRY-1234") or that otherwise doesn't
  # look like an id at all (a UUID) passes through `expand_issue_id/1`
  # unchanged.
  @bare_issue_id_regex ~r/^\d+$/

  @doc """
  Adds a comment to `issue`, resolving `comment` (asking, or opening an
  editor, if not already given - via `LinearCli.CLI.WhatFor.comment_for/2`)
  first.

  Ported from `CLI::Issue#issue_comment`.
  """
  @spec issue_comment(%Linear.Issue{}, String.t() | nil) ::
          {:ok, %Linear.Comment{}} | {:error, term()}
  def issue_comment(issue, comment) do
    body = WhatFor.comment_for(issue, comment)

    case Linear.add_comment(issue.identifier, body) do
      {:ok, created} ->
        Prompt.ok("Comment added to #{issue.identifier}")
        {:ok, created}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cancels `issue`: comments with a resolved reason, then transitions it to
  its team's cancelled workflow state.

  `opts` (Ruby's `**options`):

    * `:reason` - passed through to `LinearCli.CLI.WhatFor.reason_for/2`
    * `:trash` - forwarded to the `issueUpdate` mutation's `trashed:` input

  Ported from `CLI::Issue#cancel_issue`.
  """
  @spec cancel_issue(%Linear.Issue{}, keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def cancel_issue(issue, opts \\ []) do
    reason =
      WhatFor.reason_for(opts[:reason], four: "cancelling #{issue.identifier} - #{issue.title}")

    with {:ok, _comment} <- issue_comment(issue, reason),
         {:ok, cancel_state} <- cancelled_state_for(issue),
         {:ok, updated} <- Linear.close_issue(issue, cancel_state.id, %{trash: !!opts[:trash]}) do
      Prompt.ok("#{issue.identifier} was cancelled")
      {:ok, updated}
    end
  end

  @doc """
  Closes (or, if `opts[:cancel]` is truthy, cancels) `issue`: comments with
  a resolved reason, then transitions it to the appropriate workflow state.

  `opts` (Ruby's `**options`): `:cancel`, `:reason`, `:trash` - same meaning
  as `cancel_issue/2`'s.

  Ported from `CLI::Issue#close_issue`. Note this has its own internal
  cancelled/completed branch (mirroring Ruby exactly) even though
  `update_issue/2` never actually reaches it with `opts[:cancel]` truthy -
  `update_issue/2` dispatches to `cancel_issue/2` directly for that case,
  the same as Ruby does.
  """
  @spec close_issue(%Linear.Issue{}, keyword()) :: {:ok, %Linear.Issue{}} | {:error, term()}
  def close_issue(issue, opts \\ []) do
    cancelled = opts[:cancel]
    doing = if cancelled, do: "cancelling", else: "closing"
    done = if cancelled, do: "cancelled", else: "closed"

    reason =
      WhatFor.reason_for(opts[:reason], four: "#{doing} *#{issue.identifier} - #{issue.title}*")

    with {:ok, _comment} <- issue_comment(issue, reason),
         {:ok, workflow_state} <- state_for(cancelled, issue),
         {:ok, updated} <- Linear.close_issue(issue, workflow_state.id, %{trash: !!opts[:trash]}) do
      Prompt.ok("#{issue.identifier} was #{done}")
      {:ok, updated}
    end
  end

  defp state_for(cancelled, issue) do
    if cancelled, do: cancelled_state_for(issue), else: completed_state_for(issue)
  end

  @doc """
  Resolves `issue`'s team's single cancelled workflow state directly, or
  prompts (`LinearCli.CLI.Prompt.select/2`) among several.

  Ported from the combination of Ruby's `BaseModel#cancelled_states`
  (`workflow_states.select { |ws| CANCELLED_STATES.include? ws.type }`) and
  `CLI::WhatFor#cancelled_state_for` - see this module's moduledoc for why
  both live here. Returns `{:error, {:smells_bad, message}}` if the team has
  *no* cancelled-type workflow state - Ruby has no equivalent guard (its own
  `states.first` on an empty array is silently `nil`).
  """
  @spec cancelled_state_for(%Linear.Issue{}) ::
          {:ok, %Linear.WorkflowState{}} | {:error, term()}
  def cancelled_state_for(issue),
    do: workflow_state_for(issue, ["cancelled", "canceled"], "cancelled")

  @doc """
  Resolves `issue`'s team's single completed workflow state directly, or
  prompts (`LinearCli.CLI.Prompt.select/2`) among several.

  Ported from the combination of Ruby's `BaseModel#completed_states`
  (`workflow_states.select { |ws| ws.type == 'completed' }`) and
  `CLI::WhatFor#completed_state_for` - see this module's moduledoc. Returns
  `{:error, {:smells_bad, message}}` if the team has no completed-type
  workflow state.
  """
  @spec completed_state_for(%Linear.Issue{}) ::
          {:ok, %Linear.WorkflowState{}} | {:error, term()}
  def completed_state_for(issue), do: workflow_state_for(issue, ["completed"], "completed")

  defp workflow_state_for(issue, types, label) do
    with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id) do
      case Enum.filter(states, &(&1.type in types)) do
        [state] ->
          {:ok, state}

        [] ->
          smells_bad(
            "No #{label} workflow states found for team #{issue.team.key || issue.team.id}"
          )

        many ->
          {:ok, Prompt.select("Choose a #{label} state", Enum.map(many, &{&1.name, &1}))}
      end
    end
  end

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
  Attaches `issue` to a project matched against `project_search` among its
  team's projects (`LinearCli.CLI.Projects.project_for/2`, prompting to
  disambiguate if needed).

  Ported from `CLI::Issue#attach_project`. Like Ruby, does not guard against
  `project_search` matching nothing in an empty project list (`project_for`
  returning `nil`) - the same faithfully-ported crash risk Ruby's own
  `nil.id` would hit.
  """
  @spec attach_project(%Linear.Issue{}, String.t() | nil) ::
          {:ok, %Linear.Issue{}} | {:error, term()}
  def attach_project(issue, project_search) do
    with {:ok, projects} <- Linear.projects_by_team(issue.team.id) do
      project = Projects.project_for(projects, project_search)

      case Linear.attach_issue_to_project(issue, project.id) do
        {:ok, updated} ->
          Prompt.ok("#{issue.identifier} was attached to #{project.name}")
          {:ok, updated}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Dispatches an issue update per whichever of `opts`' keys is set, in Ruby's
  exact precedence order:

    1. `:comment` - always applied first (via `issue_comment/2`) if given,
       regardless of anything else
    2. `:close` -> `close_issue/2`
    3. `:cancel` -> `cancel_issue/2`
    4. `:pr` -> `issue_pr/2`
    5. `:project` -> `attach_project/2`
    6. otherwise, if only `:comment` was given, stop silently
    7. otherwise, warn "No action taken" and report "not updated"

  Ported from `CLI::Issue#update_issue`. Unlike every other function in this
  module, normalizes its result down to `:ok | {:error, reason}` (dropping
  the `{:ok, term}` wrapper) to match `LinearCli.CLI.run/3`'s command-handler
  contract - see this module's moduledoc.
  """
  @spec update_issue(%Linear.Issue{}, keyword()) :: :ok | {:error, term()}
  def update_issue(issue, opts \\ []) do
    with :ok <- maybe_comment(issue, opts[:comment]) do
      dispatch_update(issue, opts)
    end
  end

  defp maybe_comment(_issue, nil), do: :ok

  defp maybe_comment(issue, comment) do
    case issue_comment(issue, comment) do
      {:ok, _comment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch_update(issue, opts) do
    cond do
      opts[:close] -> normalize(close_issue(issue, opts))
      opts[:cancel] -> normalize(cancel_issue(issue, opts))
      opts[:pr] -> issue_pr(issue, opts)
      opts[:project] -> normalize(attach_project(issue, opts[:project]))
      opts[:comment] -> :ok
      true -> no_action_taken()
    end
  end

  defp no_action_taken do
    Prompt.warn("No action taken, no options specified")
    Prompt.ok("Issue was not updated")
    :ok
  end

  defp normalize({:ok, _result}), do: :ok
  defp normalize({:error, reason}), do: {:error, reason}

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
    title = WhatFor.title_for(opts[:title])
    description = WhatFor.description_for(opts[:description])
    team = WhatFor.team_for(opts[:team] || Profiles.default_team())
    labels = WhatFor.labels_for(team, opts[:labels])

    with {:ok, projects} <- Linear.projects_by_team(team.id) do
      project = Projects.project_for(projects, opts[:project] || Profiles.default_project())
      label_ids = Enum.map(labels, & &1.id)
      params = maybe_put_project_id(%{label_ids: label_ids}, project)

      Linear.create_issue(title, description, team.id, params)
    end
  end

  defp maybe_put_project_id(params, nil), do: params
  defp maybe_put_project_id(params, project), do: Map.put(params, :project_id, project.id)

  @doc """
  Expands a bare issue number (`~r/^\\d+$/`, e.g. `"1234"`) to a full
  team-prefixed identifier (`"CRY-1234"`) by resolving a team key via
  `resolve_bare_team/0`. Anything else (an already-prefixed identifier, a
  UUID) is returned unchanged.

  Team resolution order, never a hard error short of the user having no
  teams at all: the active profile's team (`LinearCli.Profiles.default_team/0`)
  -> favorited teams (`LinearCli.Favorites.list/1`, single favorite used
  directly, several prompted) -> a prompt across every team the user
  belongs to (`LinearCli.CLI.WhatFor.ask_for_team/0`).
  """
  @spec expand_issue_id(String.t()) :: String.t()
  def expand_issue_id(issue_id) do
    if Regex.match?(@bare_issue_id_regex, issue_id) do
      "#{resolve_bare_team()}-#{issue_id}"
    else
      issue_id
    end
  end

  defp resolve_bare_team do
    case Profiles.default_team() do
      nil -> resolve_bare_team_from_favorites()
      team_key -> team_key
    end
  end

  defp resolve_bare_team_from_favorites do
    case Favorites.list("team") do
      [] -> WhatFor.ask_for_team().key
      [team_key] -> team_key
      team_keys -> Prompt.select("Choose a team", Enum.map(team_keys, &{&1, &1}))
    end
  end

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
    issue_id = expand_issue_id(issue_id)

    with {:ok, me} <- resolve_me(opts),
         {:ok, [issue]} <- Linear.issues(%{ids: [issue_id]}) do
      assign_or_confirm(issue, me, issue_id)
    end
  end

  defp assign_or_confirm(%{assignee: %{id: id}} = issue, %{id: id}, issue_id) do
    Prompt.say("You are already assigned #{issue_id}")
    {:ok, issue}
  end

  defp assign_or_confirm(issue, me, issue_id) do
    Prompt.say("Assigning issue #{issue_id} to ya")
    Linear.assign_issue(issue, me.id)
  end

  defp resolve_me(opts) do
    case Keyword.fetch(opts, :me) do
      {:ok, me} -> {:ok, me}
      :error -> Linear.me()
    end
  end

  defp smells_bad(message), do: {:error, {:smells_bad, message}}
end
