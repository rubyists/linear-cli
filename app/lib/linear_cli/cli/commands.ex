defmodule LinearCli.CLI.Commands do
  @moduledoc """
  The logic behind each subcommand: fetch via `LinearCli.Linear`, display the
  result. Ported from vendor/ruby-linear-cli/lib/linear/commands/**.
  """

  alias LinearCli.CLI.{Display, IssueHelpers, Projects, Prompt, WhatFor}
  alias LinearCli.{Favorites, Git, Linear, Profiles}

  @doc "Ported from commands/whoami.rb."
  def whoami(%{flags: flags, options: options}) do
    with {:ok, user} <- Linear.me() do
      Display.show(user, %{output: options.output, teams: flags.teams})
      :ok
    end
  end

  @doc """
  Ported from commands/version.rb, extended to respect the global
  `--output json` option like every other command does - previously
  ignored it and always printed plain text.
  """
  def version(%{options: options}) do
    version = to_string(Application.spec(:linear_cli, :vsn))

    if options.output == "json" do
      IO.puts(Jason.encode!(%{version: version}))
    else
      IO.puts(version)
    end

    :ok
  end

  @doc "Ported from commands/team/list.rb. Ruby's `--mine` defaults true."
  def team_list(%{flags: flags, options: options}) do
    result = if flags.no_mine, do: Linear.teams(), else: Linear.my_teams()

    with {:ok, teams} <- result do
      Display.show(filter_favorites(teams, flags.all, "team", & &1.key), %{
        output: options.output
      })

      :ok
    end
  end

  @doc "Ported from commands/project/list.rb. Ruby's `--mine` defaults false."
  def project_list(%{flags: flags, options: options}) do
    with {:ok, projects} <- projects_for(flags, options) do
      Display.show(filter_favorites(projects, flags.all, "project", & &1.id), %{
        output: options.output
      })

      :ok
    end
  end

  defp projects_for(_flags, %{team: team_key}) when is_binary(team_key) do
    with {:ok, team} <- Linear.find_team(team_key) do
      Linear.projects_by_team(team.id)
    end
  end

  defp projects_for(%{mine: true}, _options), do: Linear.my_projects()
  defp projects_for(_flags, _options), do: Linear.projects()

  @doc """
  New in this port - Ruby has no equivalent. Favorites a team
  (`LinearCli.Favorites`) - once any team is favorited, `team list`
  defaults to showing just favorites (`--all` overrides).
  """
  def team_favorite(%{args: %{team: key}}) do
    with {:ok, team} <- Linear.find_team(key) do
      Favorites.add("team", team.key)
      Prompt.ok("Favorited team #{team.key}")
      :ok
    end
  end

  @doc "New in this port - Ruby has no equivalent. Un-favorites a team."
  def team_unfavorite(%{args: %{team: key}}) do
    with {:ok, team} <- Linear.find_team(key) do
      Favorites.remove("team", team.key)
      Prompt.ok("Un-favorited team #{team.key}")
      :ok
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Favorites a project
  (`LinearCli.Favorites`), resolved against the active team's projects,
  prompting if ambiguous. Team is resolved via `--team`, the active
  profile, or an interactive prompt. Once any project is favorited,
  `project list` defaults to showing just favorites (`--all` overrides).
  """
  def project_favorite(%{args: %{project: search}, options: options}) do
    team = WhatFor.team_for(options.team || Profiles.default_team())

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         project when not is_nil(project) <- Projects.project_for(projects, search) do
      Favorites.add("project", project.id)
      Prompt.ok("Favorited project #{project.name}")
      :ok
    else
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Un-favorites a project."
  def project_unfavorite(%{args: %{project: search}, options: options}) do
    team = WhatFor.team_for(options.team || Profiles.default_team())

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         project when not is_nil(project) <- Projects.project_for(projects, search) do
      Favorites.remove("project", project.id)
      Prompt.ok("Un-favorited project #{project.name}")
      :ok
    else
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Once any favorite of `kind` exists, narrows `records` down to just
  # those (matched via `key_fun`) - invisible to anyone who's never
  # favorited anything, since an empty favorites list leaves `records`
  # untouched. `all?` (the new `--all` flag) always shows everything,
  # bypassing the favorites lookup entirely.
  defp filter_favorites(records, true, _kind, _key_fun), do: records

  defp filter_favorites(records, _all?, kind, key_fun) do
    case Favorites.list(kind) do
      [] -> records
      favorite_values -> Enum.filter(records, &(key_fun.(&1) in favorite_values))
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Posts a status update
  (Linear's own "Project Update" feature - a journal-style status post,
  not an edit to the project's own fields) via the projectUpdateCreate
  mutation. `PROJECT` is resolved against the active team's projects,
  prompting if ambiguous. Team is resolved via `--team`, the active
  profile, or an interactive prompt.
  """
  def project_update(%{args: %{project: search}, options: options}) do
    team = WhatFor.team_for(options.team || Profiles.default_team())

    with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: search}),
         project when not is_nil(project) <- Projects.project_for(projects, search),
         {:ok, update} <-
           Linear.post_project_update(project.id, options.body, %{health: options.health}) do
      Display.show(update, %{output: options.output})
      :ok
    else
      nil -> {:error, {:smells_bad, "No project found matching #{search}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Saves a new named
  team/project bundle (`LinearCli.Profiles.create/2`) that `profile use`
  can later switch to.
  """
  def profile_create(%{args: %{name: name}, options: options}) do
    case Profiles.create(name, team: options.team, project: options.project) do
      {:ok, profile} ->
        Display.show(profile, %{output: options.output})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Lists every saved profile."
  def profile_list(%{options: options}) do
    Display.show(Profiles.list(), %{output: options.output})
    :ok
  end

  @doc """
  New in this port - Ruby has no equivalent. Switches the active profile -
  its team/project become the defaults `issue create`/`issue list` fall
  back to when `--team`/`--project` are omitted.
  """
  def profile_use(%{args: %{name: name}}) do
    case Profiles.activate(name) do
      :ok ->
        Prompt.ok("Switched to profile #{name}")
        :ok

      {:error, :not_found} ->
        {:error, {:smells_bad, "No profile named #{name}"}}
    end
  end

  @doc "New in this port - Ruby has no equivalent. Shows the active profile, if any."
  def profile_show(%{options: options}) do
    case Profiles.active() do
      nil -> Prompt.warn("No active profile")
      profile -> Display.show(profile, %{output: options.output})
    end

    :ok
  end

  @doc "New in this port - Ruby has no equivalent. Deactivates the active profile without deleting it."
  def profile_clear(_result) do
    Profiles.clear()
    Prompt.ok("Cleared active profile")
    :ok
  end

  @doc "New in this port - Ruby has no equivalent. Deletes a saved profile."
  def profile_delete(%{args: %{name: name}}) do
    case Profiles.delete(name) do
      :ok ->
        Prompt.ok("Deleted profile #{name}")
        :ok

      {:error, :not_found} ->
        {:error, {:smells_bad, "No profile named #{name}"}}
    end
  end

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
      input = %{
        ids: Enum.map(ids, &IssueHelpers.expand_issue_id/1),
        mine: !flags.no_mine,
        unassigned: flags.unassigned,
        team_key: team_key,
        project_id: project_id,
        all: Map.get(flags, :all, false),
        status: Map.get(options, :status) || []
      }

      with {:ok, issues} <- Linear.issues(input) do
        Display.show(issues, %{output: options.output, full: flags.full})
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

  @doc """
  Ported from commands/issue/create.rb: resolves every field
  (`LinearCli.CLI.IssueHelpers.make_da_issue!/1`), optionally self-assigns it
  (`prompt.yes?('Do you want to take this issue?')`), displays it, then, if
  `--dev` was given, chains straight into the same flow as `issue_develop/2`
  (Ruby: `Rubyists::Linear::CLI::Issue::Develop.new.call(issue_id: issue.id,
  **options)`).

  `opts` isn't part of Ruby's `call(**options)` arity - it exists purely to
  inject test doubles into whatever this command chains into: `:me`
  (`gimme_da_issue!/2`, both for the self-assign prompt and, if `--dev`
  fires, `run_develop/2`'s own re-fetch), `:cwd`
  (`LinearCli.Git.checkout_branch/2`/`pull_or_push_new_branch!/2`, only
  reached with `--dev`). Real callers (`LinearCli.CLI.main/2`) omit it.
  """
  @spec issue_create(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_create(result, opts \\ [])

  def issue_create(%{options: options, flags: flags}, opts) do
    create_opts = [
      title: options.title,
      description: options.description,
      team: options.team,
      labels: options.labels,
      project: options.project
    ]

    with {:ok, issue} <- IssueHelpers.make_da_issue!(create_opts),
         :ok <- maybe_take(issue, opts) do
      Display.show(issue, %{output: options.output})
      if flags.develop, do: run_develop(issue.id, opts), else: :ok
    end
  end

  defp maybe_take(issue, opts) do
    if Prompt.yes?("Do you want to take this issue?") do
      case IssueHelpers.gimme_da_issue!(issue.id, opts) do
        {:ok, _updated} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @doc """
  Ported from commands/issue/develop.rb: resolves/self-assigns `issue_id`
  (`LinearCli.CLI.IssueHelpers.gimme_da_issue!/2`), checks out its
  `branch_name` (creating it first if it doesn't exist locally yet), then
  pulls it (or, if there's no upstream tracking branch yet, pushes it to
  `origin` and sets one up).

  `opts` (this port's addition, not part of Ruby's `call(issue_id:,
  **options)`) forwards to `LinearCli.Git.checkout_branch/2`/
  `pull_or_push_new_branch!/2` (`:cwd`) and
  `LinearCli.CLI.IssueHelpers.gimme_da_issue!/2` (`:me`) - pass overrides in
  tests so this never shells out to real git or hits a real `viewer` query;
  real callers omit it.
  """
  @spec issue_develop(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_develop(result, opts \\ [])
  def issue_develop(%{args: %{issue_id: issue_id}}, opts), do: run_develop(issue_id, opts)

  defp run_develop(issue_id, opts) do
    with {:ok, issue} <- IssueHelpers.gimme_da_issue!(issue_id, opts),
         {:ok, _branch} <- Git.checkout_branch(issue.branch_name, opts) do
      Prompt.ok("Checked out branch #{issue.branch_name}")
      finish_pull_or_push(issue.branch_name, opts)
    end
  end

  # Ported from `SubCommands#pull_or_push_new_branch!`'s own prompt calls
  # (`prompt.warn`/`prompt.ok`, printed around the push+set-upstream fallback
  # only) plus `Issue::Develop#call`'s trailing `prompt.ok 'Ready to
  # develop!'` (printed unconditionally, after either branch).
  defp finish_pull_or_push(branch_name, opts) do
    case Git.pull_or_push_new_branch!(branch_name, opts) do
      {:ok, {:pulled, _output}} ->
        Prompt.ok("Ready to develop!")
        :ok

      {:ok, {:pushed_new_branch, _branch_name}} ->
        Prompt.warn("Upstream branch not found, pushing local #{branch_name} to origin")
        Prompt.ok("Set upstream to origin/#{branch_name}")
        Prompt.ok("Ready to develop!")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ported from commands/issue/pr.rb: resolves/self-assigns `issue_id`, checks
  out its branch (creating it first if needed - no pull/push here, unlike
  `issue_develop/2`), then opens a PR via
  `LinearCli.CLI.IssueHelpers.issue_pr/2`.

  `opts` (this port's addition): `:cwd` (forwarded to
  `LinearCli.Git.checkout_branch/2`), `:me` (forwarded to
  `gimme_da_issue!/2`), `:runner` (forwarded to `issue_pr/2`, so this never
  shells out to a real `gh` in tests). Real callers omit it.
  """
  @spec issue_pr(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_pr(result, opts \\ [])

  def issue_pr(%{args: %{issue_id: issue_id}, options: options}, opts) do
    with {:ok, issue} <- IssueHelpers.gimme_da_issue!(issue_id, opts),
         {:ok, _branch} <- Git.checkout_branch(issue.branch_name, opts) do
      Prompt.ok("Checked out branch #{issue.branch_name}")

      pr_opts =
        [title: options.title, description: options.description]
        |> maybe_put(:runner, opts[:runner])

      IssueHelpers.issue_pr(issue, pr_opts)
    end
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  @doc """
  Ported from commands/issue/take.rb: self-assigns every issue id in
  `unknown` (Ruby's `issue_ids:`, a variadic positional argument - Optimus
  has no declared-arity equivalent to `type: :array` positional args, so,
  like `issue_list/1`'s own `ids`, it's captured via the subcommand's
  `allow_unknown_args: true` + the parse result's `unknown` list), skipping
  (and warning about) any id that doesn't exist rather than aborting the
  whole batch - matching Ruby's `rescue NotFoundError => e ... next` inside
  its `filter_map`.

  `opts` (this port's addition) forwards to
  `LinearCli.CLI.IssueHelpers.gimme_da_issue!/2` (`:me`); real callers omit
  it.
  """
  @spec issue_take(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_take(result, opts \\ [])

  def issue_take(%{unknown: issue_ids, options: options}, opts) do
    opts = maybe_put_status(opts, Map.get(options, :status))

    with {:ok, updates} <- take_issues(issue_ids, opts) do
      Display.show(updates, %{output: options.output})
      :ok
    end
  end

  defp maybe_put_status(opts, nil), do: opts
  defp maybe_put_status(opts, status), do: Keyword.put(opts, :status, status)

  defp take_issues(issue_ids, opts) do
    issue_ids
    |> Enum.reduce_while({:ok, []}, fn issue_id, {:ok, acc} ->
      case IssueHelpers.gimme_da_issue!(issue_id, opts) do
        {:ok, issue} ->
          {:cont, {:ok, [issue | acc]}}

        {:error, %Ash.Error.Unknown{errors: [%{value: [{:not_found, id}]} | _]}} ->
          Prompt.warn("No issue found with id #{id}")
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  @doc """
  Ported from commands/issue/update.rb: looks up every issue id in `unknown`
  (see `issue_take/2`'s doc for why this is a variadic positional captured
  via `unknown` rather than a declared Optimus arg) and dispatches
  `LinearCli.CLI.IssueHelpers.update_issue/2` against each, per whichever
  flags/options were given.

  Ports `raise SmellsBad, 'No issue IDs provided!' if issue_ids.empty?` as
  `{:error, {:smells_bad, "No issue IDs provided!"}}` (mapped to exit 22 by
  `LinearCli.CLI.handle_error/3`). Ruby's second guard - `raise SmellsBad,
  '...' if options[:pr] && issue_ids.size > 1` - has no equivalent here:
  the real `update.rb` never actually registers a `--pr` option/flag
  (`options[:pr]` can never be truthy there either), so it's dead code in
  the original and isn't ported.
  """
  @spec issue_update(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_update(%{unknown: issue_ids, options: options, flags: flags}) do
    with :ok <- validate_issue_ids(issue_ids),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &IssueHelpers.expand_issue_id/1)}) do
      update_opts = [
        comment: options.comment,
        description: Map.get(options, :description),
        project: options.project,
        cancel: flags.cancel,
        close: flags.close,
        reason: options.reason,
        trash: flags.trash
      ]

      Enum.reduce_while(issues, :ok, fn issue, :ok ->
        case IssueHelpers.update_issue(issue, update_opts) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp validate_issue_ids([]), do: {:error, {:smells_bad, "No issue IDs provided!"}}
  defp validate_issue_ids(_issue_ids), do: :ok

  @doc """
  Changes the workflow state of an issue.

  With `--status`/`-s`, matches the given name against the issue's team's
  workflow states (case-insensitive exact, then unique prefix). Without it,
  prompts interactively via `LinearCli.CLI.Prompt.select/2`.

  With `--comment`/`-m`, adds a comment to the issue before transitioning.
  """
  @spec issue_status(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_status(%{args: %{issue_id: issue_id}, options: options}) do
    expanded_id = IssueHelpers.expand_issue_id(issue_id)

    with {:ok, [issue]} <- Linear.issues(%{ids: [expanded_id]}),
         {:ok, states} <- Linear.workflow_states_by_team(issue.team.id),
         {:ok, target_state} <- resolve_target_state(states, options.status),
         :ok <- maybe_add_status_comment(issue, options.comment),
         {:ok, updated} <- Linear.set_issue_status(issue, target_state.id) do
      Display.show(updated, %{output: options.output})

      if options.output != "json",
        do: Prompt.ok("#{updated.identifier} status set to #{target_state.name}")

      :ok
    end
  end

  defp resolve_target_state(states, nil) do
    choices = Enum.sort_by(states, & &1.position) |> Enum.map(&{&1.name, &1})
    {:ok, Prompt.select("Choose a status", choices)}
  end

  defp resolve_target_state(states, name) do
    normalized_name = String.downcase(name)

    states
    |> Enum.filter(&(String.downcase(&1.name) == normalized_name))
    |> use_prefix_matches_if_empty(states, normalized_name)
    |> resolve_state_matches(states, name)
  end

  defp use_prefix_matches_if_empty([], states, name) do
    Enum.filter(states, &String.starts_with?(String.downcase(&1.name), name))
  end

  defp use_prefix_matches_if_empty(matches, _states, _name), do: matches

  defp resolve_state_matches([state], _states, _name), do: {:ok, state}

  defp resolve_state_matches([], states, name) do
    available = Enum.map_join(states, ", ", & &1.name)
    {:error, {:smells_bad, "Unknown status #{inspect(name)}. Available: #{available}"}}
  end

  defp resolve_state_matches(matches, _states, name) do
    ambiguous = Enum.map_join(matches, ", ", & &1.name)
    {:error, {:smells_bad, "Ambiguous status #{inspect(name)}: matches #{ambiguous}"}}
  end

  defp maybe_add_status_comment(_issue, nil), do: :ok

  defp maybe_add_status_comment(issue, comment) do
    case IssueHelpers.issue_comment(issue, comment) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_optional_status(_issue, nil), do: {:ok, nil}

  defp resolve_optional_status(issue, name) do
    with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id),
         {:ok, state} <- resolve_target_state(states, name) do
      {:ok, state.id}
    end
  end

  @doc """
  Assigns an issue to a team member.

  With `--assignee`/`-a`, matches the given name against the issue's team's
  members (case-insensitive exact, then unique prefix). Without it, prompts
  interactively via `LinearCli.CLI.Prompt.select/2`.
  """
  @spec issue_assign(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_assign(%{args: %{issue_id: issue_id}, options: options}) do
    expanded_id = IssueHelpers.expand_issue_id(issue_id)

    with {:ok, [issue]} <- Linear.issues(%{ids: [expanded_id]}),
         {:ok, members} <- Linear.team_members(issue.team.id),
         :ok <- guard_has_members(members, issue),
         {:ok, target_member} <- resolve_target_member(members, options.assignee),
         {:ok, state_id} <- resolve_optional_status(issue, Map.get(options, :status)),
         {:ok, updated} <- Linear.assign_issue(issue, target_member.id, %{state_id: state_id}) do
      Display.show(updated, %{output: options.output})

      if options.output != "json" do
        msg = "#{updated.identifier} assigned to #{target_member.name}"

        msg =
          if updated.state,
            do: "#{msg} and set to #{updated.state.name}",
            else: msg

        Prompt.ok(msg)
      end

      :ok
    end
  end

  defp guard_has_members([], issue) do
    {:error,
     {:smells_bad, "No assignable members found for team #{issue.team.key || issue.team.id}"}}
  end

  defp guard_has_members(_members, _issue), do: :ok

  defp resolve_target_member(members, nil) do
    choices = Enum.sort_by(members, & &1.name) |> Enum.map(&{&1.name, &1})
    {:ok, Prompt.select("Choose an assignee", choices)}
  end

  defp resolve_target_member(members, name) do
    normalized = String.downcase(name)

    members
    |> Enum.filter(&(String.downcase(&1.name) == normalized))
    |> use_prefix_member_matches_if_empty(members, normalized)
    |> resolve_member_matches(members, name)
  end

  defp use_prefix_member_matches_if_empty([], members, name) do
    Enum.filter(members, &String.starts_with?(String.downcase(&1.name), name))
  end

  defp use_prefix_member_matches_if_empty(matches, _members, _name), do: matches

  defp resolve_member_matches([member], _members, _name), do: {:ok, member}

  defp resolve_member_matches([], members, name) do
    available = Enum.map_join(Enum.sort_by(members, & &1.name), ", ", & &1.name)
    {:error, {:smells_bad, "Unknown assignee #{inspect(name)}. Available: #{available}"}}
  end

  defp resolve_member_matches(matches, _members, name) do
    ambiguous = Enum.map_join(matches, ", ", & &1.name)
    {:error, {:smells_bad, "Ambiguous assignee #{inspect(name)}: matches #{ambiguous}"}}
  end
end
