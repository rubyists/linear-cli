defmodule LinearCli.CLI.Commands do
  @moduledoc """
  The logic behind each subcommand: fetch via `LinearCli.Linear`, display the
  result. Ported from vendor/ruby-linear-cli/lib/linear/commands/**.
  """

  alias LinearCli.CLI.{Display, IssueHelpers, Projects, Prompt, WhatFor}
  alias LinearCli.{Favorites, Git, Linear, Profiles}

  @max_concurrent_issue_updates 20

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
  ignored it and always printed plain text. The hidden Markdown renders make
  this command a complete release smoke test for the MDEx and Syntect NIFs,
  Marcli's syntax-highlighting integration, and the application boot path.
  """
  def version(%{options: options}) do
    verify_markdown_runtime!()
    version = to_string(Application.spec(:linear_cli, :vsn))

    if options.output == "json" do
      IO.puts(Jason.encode!(%{version: version}))
    else
      IO.puts(version)
    end

    :ok
  end

  defp verify_markdown_runtime! do
    theme = Marcli.Theme.default()
    elixir = Marcli.render("```elixir\ndef smoke, do: :ok\n```")
    ruby = Marcli.render("```ruby\ndef smoke; :ok; end\n```")

    elixir_keyword = theme.syntax.keyword_declaration <> "def" <> theme.reset
    ruby_keyword = theme.syntax.keyword_type <> "def" <> theme.reset

    unless String.contains?(elixir, elixir_keyword) and String.contains?(ruby, ruby_keyword) do
      raise "Markdown syntax-highlighting runtime is unavailable"
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
        state: Map.get(options, :state) || [],
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
        status: Map.get(options, :status),
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

  @doc """
  Moves issues to a target project.

  Two modes:
  - **ID-based** (EXT-9): `ISSUE_ID... --project P [--team T]` — moves the
    listed issues to the named project, resolved per-issue from the issue's
    own team or the given `--team`. Concurrent apply, same pattern as
    `issue_status/1`.
  - **Bulk project-to-project** (Phase 12): `--from P --to P [--team T]` —
    lists all open issues (or all with `--all`) from the source project and
    fans out mutations to the target project concurrently.

  With `--dry-run`, prints the planned moves without mutating.
  Without `--yes`, asks for confirmation before applying.
  """
  @spec issue_move(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_move(%{unknown: issue_ids, options: options, flags: flags}) do
    cond do
      options.from && options.to ->
        move_issues_by_project(options, flags)

      options.from || options.to ->
        {:error,
         {:smells_bad, "--from and --to must both be given for bulk project-to-project mode"}}

      true ->
        move_issues_by_id(issue_ids, options, flags)
    end
  end

  defp move_issues_by_id(issue_ids, options, flags) do
    with :ok <- validate_issue_ids(issue_ids),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &IssueHelpers.expand_issue_id/1)}),
         {:ok, project} <- resolve_move_project(issues, options) do
      print_move_plan(issues, project, options.output)
      execute_moves_if_confirmed(issues, project, flags, options.output)
    end
  end

  defp resolve_move_project(issues, options) do
    with {:ok, tid} <- resolve_move_team_id(options.team || Profiles.default_team(), issues),
         {:ok, projects} <- Linear.projects_by_team(tid, %{search: options.project}) do
      project_result(Projects.project_for(projects, options.project), options.project)
    end
  end

  defp project_result(nil, search),
    do: {:error, {:smells_bad, "No project found matching #{inspect(search)}"}}

  defp project_result(project, _search), do: {:ok, project}

  defp resolve_move_team_id(nil, issues), do: {:ok, hd(issues).team.id}

  defp resolve_move_team_id(key, _issues) do
    with {:ok, team} <- Linear.find_team(key), do: {:ok, team.id}
  end

  defp execute_moves_if_confirmed(_issues, _project, %{dry_run: true}, _output), do: :ok

  defp execute_moves_if_confirmed(issues, project, %{yes: true}, output),
    do: apply_moves(issues, project, output)

  defp execute_moves_if_confirmed(issues, project, _flags, output) do
    if Prompt.yes?("Proceed with move?"),
      do: apply_moves(issues, project, output),
      else: Prompt.warn("Move cancelled")
  end

  defp print_move_plan(issues, project, output) when output != "json" do
    Enum.each(issues, fn issue ->
      Prompt.say("#{issue.identifier} -> #{project.name}")
    end)
  end

  defp print_move_plan(_issues, _project, _output), do: :ok

  defp apply_moves(issues, project, output) do
    issues
    |> Task.async_stream(
      fn issue -> apply_move(issue, project) end,
      max_concurrency: min(length(issues), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, updated}}, {:ok, acc} -> {:cont, {:ok, [updated | acc]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> display_moves_result(project, output)
  end

  defp display_moves_result({:ok, updated_issues}, project, output) do
    updated_issues = Enum.reverse(updated_issues)
    Display.show(one_or_many(updated_issues), %{output: output})
    print_move_results(updated_issues, project, output)
    :ok
  end

  defp display_moves_result(error, _project, _output), do: error

  defp print_move_results(updated_issues, project, output) when output != "json" do
    Enum.each(updated_issues, fn updated ->
      Prompt.ok("#{updated.identifier} moved to #{project.name}")
    end)
  end

  defp print_move_results(_updated_issues, _project, _output), do: :ok

  defp apply_move(issue, project) do
    Linear.attach_issue_to_project(issue, project.id)
  end

  defp validate_issue_ids([]), do: {:error, {:smells_bad, "No issue IDs provided!"}}
  defp validate_issue_ids(_issue_ids), do: :ok

  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  defp move_issues_by_project(options, flags) do
    team_fn = fn -> WhatFor.team_for(options.team || Profiles.default_team()) end

    with {:ok, source} <- resolve_bulk_project(options.from, team_fn),
         {:ok, target} <- resolve_bulk_project(options.to, team_fn),
         :ok <- guard_different_projects(source, target),
         {:ok, issues} <- Linear.issues(%{project_id: source.id, mine: false, all: flags.all}) do
      cond do
        issues == [] ->
          label = if flags.all, do: "issues", else: "open issues"
          Prompt.ok("No #{label} in #{source.name} to move")
          :ok

        flags.dry_run ->
          Display.show(one_or_many(issues), %{output: options.output})
          Prompt.ok("Would move #{length(issues)} issue(s) from #{source.name} to #{target.name}")
          :ok

        not flags.yes and
            not Prompt.yes?(
              "Move #{length(issues)} issue(s) from #{source.name} to #{target.name}?"
            ) ->
          Prompt.warn("Move cancelled")

        true ->
          with {:ok, pairs} <- apply_project_moves(issues, target) do
            show_move_results(pairs, source, target, options.output)
          end
      end
    end
  end

  defp resolve_bulk_project(value, team_fn) do
    if Regex.match?(@uuid_regex, value) do
      short_name = String.slice(value, 0, 8) <> "…"
      {:ok, struct(LinearCli.Linear.Project, %{id: value, name: short_name})}
    else
      team = team_fn.()

      with {:ok, projects} <- Linear.projects_by_team(team.id, %{search: value}),
           project when not is_nil(project) <- Projects.project_for(projects, value) do
        {:ok, project}
      else
        nil -> {:error, {:smells_bad, "No project found matching #{value}"}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp guard_different_projects(%{id: id}, %{id: id}),
    do: {:error, {:smells_bad, "source and target are the same project"}}

  defp guard_different_projects(_source, _target), do: :ok

  defp apply_project_moves(issues, target) do
    issues
    |> Task.async_stream(
      fn issue ->
        case Linear.attach_issue_to_project(issue, target.id) do
          {:ok, updated} -> {:ok, {issue, updated}}
          {:error, reason} -> {:error, reason}
        end
      end,
      max_concurrency: min(length(issues), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, pair}}, {:ok, acc} -> {:cont, {:ok, [pair | acc]}}
      {:ok, {:error, reason}}, {:ok, _acc} -> {:halt, {:error, reason}}
      {:exit, reason}, {:ok, _acc} -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end)
  end

  defp show_move_results(pairs, source, target, output) do
    if output == "json" do
      Display.show(one_or_many(Enum.map(pairs, &elem(&1, 1))), %{output: "json"})
    else
      Enum.each(pairs, fn {orig, _updated} ->
        Prompt.ok("#{orig.identifier} moved to #{target.name}")
      end)

      Prompt.ok("Moved #{length(pairs)} issue(s) from #{source.name} to #{target.name}")
    end

    :ok
  end

  @doc """
  Changes the workflow state of one or more issues. Optimus captures the IDs in
  `unknown`, since it has no variadic positional-argument type.

  With `--status`/`-s`, matches the given name against the issue's team's
  workflow states (case-insensitive exact, then unique prefix). Without it,
  prompts interactively via `LinearCli.CLI.Prompt.select/2`.

  With `--comment`/`-m`, adds a comment to each issue before transitioning it.
  Mutations for separate issues run concurrently with a limit of 20 in flight.
  """
  @spec issue_status(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_status(%{unknown: issue_ids, options: options}) do
    with :ok <- validate_issue_ids(issue_ids),
         {:ok, issues} <-
           Linear.issues(%{ids: Enum.map(issue_ids, &IssueHelpers.expand_issue_id/1)}),
         {:ok, planned_updates} <- plan_status_updates(issues, options.status),
         {:ok, completed_updates} <- apply_status_updates(planned_updates, options.comment) do
      show_status_updates(completed_updates, options.output)
    end
  end

  defp plan_status_updates(issues, status) do
    issues
    |> Enum.reduce_while({:ok, []}, fn issue, {:ok, updates} ->
      with {:ok, states} <- Linear.workflow_states_by_team(issue.team.id),
           {:ok, target_state} <- resolve_target_state(states, status) do
        {:cont, {:ok, [{issue, target_state} | updates]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_status_updates()
  end

  defp apply_status_updates([], _comment), do: {:ok, []}

  defp apply_status_updates(planned_updates, comment) do
    planned_updates
    |> Task.async_stream(
      fn {issue, target_state} ->
        apply_status_update(issue, target_state, comment)
      end,
      max_concurrency: min(length(planned_updates), @max_concurrent_issue_updates),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, update}}, {:ok, updates} ->
        {:cont, {:ok, [update | updates]}}

      {:ok, {:error, reason}}, {:ok, _updates} ->
        {:halt, {:error, reason}}

      {:exit, reason}, {:ok, _updates} ->
        {:halt, {:error, {:task_exit, reason}}}
    end)
    |> reverse_status_updates()
  end

  defp apply_status_update(issue, target_state, comment) do
    with :ok <- maybe_add_status_comment(issue, comment),
         {:ok, updated} <- Linear.set_issue_status(issue, target_state.id) do
      {:ok, {updated, target_state}}
    end
  end

  defp reverse_status_updates({:ok, updates}), do: {:ok, Enum.reverse(updates)}
  defp reverse_status_updates(error), do: error

  defp show_status_updates(completed_updates, output) do
    updated_issues = Enum.map(completed_updates, &elem(&1, 0))
    Display.show(one_or_many(updated_issues), %{output: output})

    if output != "json" do
      Enum.each(completed_updates, fn {updated, target_state} ->
        Prompt.ok("#{updated.identifier} status set to #{target_state.name}")
      end)
    end

    :ok
  end

  defp one_or_many([one]), do: one
  defp one_or_many(many), do: many

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
