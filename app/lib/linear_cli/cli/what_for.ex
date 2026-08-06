defmodule LinearCli.CLI.WhatFor do
  @moduledoc """
  The "ask the user for X unless it was already given on the command line"
  helpers.

  Ported from `Rubyists::Linear::CLI::WhatFor`
  (vendor/ruby-linear-cli/lib/linear/cli/what_for.rb) plus the two helpers it
  leans on from `Rubyists::Linear::CLI::SubCommands`
  (vendor/ruby-linear-cli/lib/linear/cli/sub_commands.rb) that only exist to
  support `team_for` (`ask_for_team`/`choose_a_team!`).

  All interactive fallbacks go through `LinearCli.CLI.Prompt` (replacing
  Ruby's `TTY::Prompt`/`TTY::Editor`), and are testable the exact same way
  that module documents: `ExUnit.CaptureIO.capture_io/2` with a scripted
  `:input` for anything that reads a line/selection, and `Prompt.edit/2`'s
  `:editor` option for anything that shells out to an external editor.

  ## Two small resource additions this phase needed

  `team_for/1`'s key-given branch and `labels_for/2`'s no-`labels`-given
  branch each need a Linear lookup that didn't exist anywhere yet - only
  `LinearCli.Linear.my_teams/0` (Ruby's `Team.mine`) and
  `LinearCli.Linear.labels_by_names/1` (Ruby's `Label.find_all_by_name`) did.
  Added, following this codebase's own established "by X" manual-read
  pattern (see `LinearCli.Linear.Project.Read.ByTeam`,
  `LinearCli.Linear.WorkflowState.Read.ByTeam`):

    * `LinearCli.Linear.find_team/1` (Team action `:find`, `get?: true`) -
      Ruby: `BaseModel::ClassMethods#find`, a `team(id: $id)` node lookup.
    * `LinearCli.Linear.labels_by_team/1` (Label action `:by_team`) - Ruby:
      `Team#labels`, a `team(id: $id) { labels(...) }` lookup, filtered
      (server-side, Ruby's `BaseFilter`) to exclude release/platform labels
      and (client-side, Ruby's `filter_map`) to exclude group labels and
      labels that belong to a group.

  ## Deliberate deviations from the Ruby source

  Every deviation below is because the thing Ruby relied on either doesn't
  exist in this port (`TTY::Markdown`, `SmellsBad`, a `Logger`) or behaves
  differently by construction (`Owl.IO.open_in_editor/2` raises on a failed
  editor command instead of returning a falsy status) - see each function's
  own doc for specifics:

    * `reason_for/2`'s `four:` heading is interpolated as plain text - there
      is no `TTY::Markdown`-equivalent renderer here to reproduce Ruby's
      `TTY::Markdown.parse(four)` terminal formatting.
    * Anywhere Ruby `raise`s a custom `SmellsBad` error, this raises a plain
      `RuntimeError` (`raise "message"`) instead - there is no `SmellsBad`
      exception in this port, and this codebase's own error handling
      (`LinearCli.CLI.handle_error/3`) already has a generic
      `rescue StandardError`-equivalent catch-all for exactly this.
    * `pr_description_for/1` always returns the edited (or asked-for)
      description as a plain `String.t()`, never a Ruby-style `Tempfile`
      handle - the tempfile was only ever an implementation detail for
      later passing `--body-file` to `gh pr create`, which is
      `CLI::Issue#create_pr!`/`#issue_pr`'s concern, not this module's, and
      isn't part of this phase's scope.
    * `pr_description_for/1` also drops Ruby's "if the editor failed to
      open, ask via a one-line prompt instead" fallback:
      `Owl.IO.open_in_editor/2` has no recoverable failure signal to branch
      on (a failed editor command raises via a `{_, 0} = System.shell(...)`
      match, it doesn't return a falsy status like Ruby's
      `TTY::Editor.open` does) - see `vendor/owl/lib/owl/io.ex`.
    * `ask_for_team/0` (this port's stand-in for
      `CLI::SubCommands#choose_a_team!`) returns the already-fetched `Team`
      the user picked directly, instead of Ruby's redundant
      `Team.find(selected_key)` re-fetch after the prompt - the same
      simplification `LinearCli.CLI.Projects.ask_for_projects/2` already
      makes relative to its own Ruby source.
    * `pr_type_for/1` always returns a `String.t()` (e.g. `"fix"`), where
      Ruby's two branches disagree (a plain `String` from the regex-match
      branch, a `Symbol` from `PR_TYPE_SELECTIONS`'s inverted-hash values on
      the prompted branch) - harmless there only because `pr_title_for`
      immediately stringifies it (`Array#join`/string interpolation); this
      port just picks the one consistent type up front.
  """

  alias LinearCli.CLI.Prompt
  alias LinearCli.Linear

  # Ported from Ruby's `WhatFor::PR_TYPES` (a `TODO: Make this configurable`
  # in the original). An ordered keyword list, not a `Map`, for the same
  # reason `LinearCli.CLI.Prompt.select/2`/`multi_select/2` take ordered
  # `[{label, value}]` lists rather than `Map`s: Ruby `Hash`es preserve
  # insertion order and this menu's display order depends on it.
  @pr_types [
    fix: "Bug fixes",
    feat: "New feature work",
    chore: "Chores and maintenance",
    eyes: "Observability, metrics",
    test: "Testing code",
    perf: "Performance related work",
    refactor: "Code refactoring",
    docs: "Documentation Updates",
    sec: "Security-related, including dependency updates",
    style: "Style updates",
    ci: "Continuous integration related",
    db: "Database-Related (migrations, models, etc)"
  ]

  # Ported from Ruby's `WhatFor::PR_TYPE_SELECTIONS` (`PR_TYPES.invert`) -
  # `LinearCli.CLI.Prompt.select/2`'s `[{label, value}]` shape already *is*
  # the "description => type" mapping Ruby's inverted hash produces, so no
  # separate inversion step is needed here.
  @pr_type_choices Enum.map(@pr_types, fn {type, description} -> {description, type} end)

  # Ported from Ruby's `WhatFor::ALLOWED_PR_TYPES`
  # (`/#{PR_TYPES.keys.join("|")}/`).
  @allowed_pr_types Enum.map_join(@pr_types, "|", fn {type, _description} -> to_string(type) end)

  # Ported from Ruby's `pr_type_for`'s `/^(#{ALLOWED_PR_TYPES})/io` - anchored
  # at the start of the title, case-insensitive, no trailing-boundary
  # requirement (so e.g. a title starting "fixture" would match "fix" - a
  # faithful port of Ruby's own regex, not something this port fixes).
  @pr_type_prefix_regex Regex.compile!("^(#{@allowed_pr_types})", "i")

  # Ported from Ruby's `pr_title_for`'s
  # `/(?:#{ALLOWED_PR_TYPES})(\([^)]+\))? /o` - unanchored (matches the
  # pattern anywhere in the title, not just at the start) and case-sensitive
  # (no `i` flag in the original), exactly as Ruby has it.
  @pr_summary_strip_regex Regex.compile!("(?:#{@allowed_pr_types})(\\([^)]+\\))? ")

  # Ported from Ruby's `pr_scope_for`'s `/^\w+\(([^)]+)\)/`.
  @pr_scope_regex ~r/^\w+\(([^)]+)\)/

  @doc """
  Returns `title` unchanged if given, otherwise prompts for one.

  Ported from `WhatFor#title_for`.
  """
  @spec title_for(String.t() | nil) :: String.t() | nil
  def title_for(title \\ nil)
  def title_for(nil), do: Prompt.ask("Title:")
  def title_for(title), do: title

  @doc """
  Returns `description` unchanged if given (and not `"-"`), otherwise asks
  for one (or opens an editor, via `ask_or_edit/2`, if the answer is `"-"`).

  Ported from `WhatFor#description_for`.
  """
  @spec description_for(String.t() | nil) :: String.t()
  def description_for(description \\ nil), do: ask_or_edit(description, "Description")

  @doc """
  Resolves `key` to a `LinearCli.Linear.Team`: looks it up directly if given,
  otherwise falls back to `ask_for_team/0`.

  Ported from `WhatFor#team_for`. Raises (a plain `RuntimeError` - see the
  moduledoc's "Deliberate deviations" section) if `key` doesn't resolve to
  any team, matching Ruby's `Team.find`/`NotFoundError`.
  """
  @spec team_for(String.t() | nil) :: %Linear.Team{}
  def team_for(key \\ nil)
  def team_for(nil), do: ask_for_team()

  def team_for(key) do
    case Linear.find_team(key) do
      {:ok, team} -> team
      {:error, reason} -> raise "No team found with id #{key} (#{inspect(reason)})"
    end
  end

  @doc """
  Ported from Ruby's `CLI::SubCommands#ask_for_team`: fetches
  `LinearCli.Linear.my_teams/0`, returning the sole team directly if there's
  exactly one, prompting (`LinearCli.CLI.Prompt.select/2`) across all of them
  if there's more than one, and raising if there are none.
  """
  @spec ask_for_team() :: %Linear.Team{}
  def ask_for_team do
    case Linear.my_teams() do
      {:ok, [team]} ->
        team

      {:ok, []} ->
        raise "No team given and none found for you " <>
                "(try joining a team or use a team id from `lc teams --no-mine`)"

      {:ok, teams} ->
        Prompt.select("Choose a team", Enum.map(teams, &{&1.name, &1}))

      {:error, reason} ->
        raise "Could not fetch your teams (#{inspect(reason)})"
    end
  end

  @doc """
  If `labels` is given (any list, including `[]` - matching Ruby's
  truthiness check on an array), looks them up by name via
  `LinearCli.Linear.labels_by_names/1`. Otherwise fetches the team's labels
  (`LinearCli.Linear.labels_by_team/1`) and prompts
  (`LinearCli.CLI.Prompt.multi_select/2`) across them.

  Ported from `WhatFor#labels_for`. Always returns a plain list of
  `LinearCli.Linear.Label`s (or raises), unifying Ruby's two branches
  (`Label.find_all_by_name` vs. `prompt.multi_select`), which likewise both
  return plain arrays.
  """
  @spec labels_for(%Linear.Team{}, [String.t()] | nil) :: [%Linear.Label{}]
  def labels_for(team, labels \\ nil)

  def labels_for(_team, labels) when is_list(labels) do
    trimmed = Enum.map(labels, &String.trim/1)

    case Linear.labels_by_names(trimmed) do
      {:ok, found} -> found
      {:error, reason} -> raise "Could not find labels #{inspect(trimmed)} (#{inspect(reason)})"
    end
  end

  def labels_for(team, nil) do
    case Linear.labels_by_team(team.id) do
      {:ok, labels} -> Prompt.multi_select("Labels:", Enum.map(labels, &{&1.name, &1}))
      {:error, reason} -> raise "Could not fetch labels for team #{team.id} (#{inspect(reason)})"
    end
  end

  @doc """
  Returns `reason` unchanged if given (and not `"-"`), otherwise asks for one
  (or opens an editor, via `ask_or_edit/2`, if the answer is `"-"`).

  `opts[:four]`, when given, is interpolated into the question as
  `"Reason for \#{four}"` instead of the bare `"Reason"` - Ruby renders `four`
  through `TTY::Markdown.parse/1` first for terminal-formatted output; this
  port interpolates it as plain text (see the moduledoc's "Deliberate
  deviations" section - there's no markdown-renderer equivalent here).

  Ported from `WhatFor#reason_for`.
  """
  @spec reason_for(String.t() | nil, keyword()) :: String.t()
  def reason_for(reason \\ nil, opts \\ [])

  def reason_for(reason, opts) do
    question =
      case Keyword.get(opts, :four) do
        nil -> "Reason"
        four -> "Reason for #{four}"
      end

    ask_or_edit(reason, question)
  end

  @doc """
  Returns `comment` unchanged if given (and not `"-"`), otherwise asks for
  one (or opens an editor if the answer is `"-"`), scoped to `issue`.

  Ported from `WhatFor#comment_for`.
  """
  @spec comment_for(%Linear.Issue{}, String.t() | nil) :: String.t()
  def comment_for(issue, comment) do
    ask_or_edit(comment, "Comment for #{issue.identifier} - #{issue.title}")
  end

  @doc """
  Proposes a Conventional-Commits-style PR title for `issue`
  (`"<type>(<scope>): <identifier> - <summary>"`, scope omitted if none),
  built from `pr_type_for/1` and `pr_scope_for/1`, and asks the user to
  confirm or override it.

  Ported from `WhatFor#pr_title_for`.
  """
  @spec pr_title_for(%Linear.Issue{}) :: String.t()
  def pr_title_for(issue) do
    type = pr_type_for(issue)
    scope = pr_scope_for(issue.title)
    scope_suffix = if scope, do: "(#{scope})", else: ""
    summary = Regex.replace(@pr_summary_strip_regex, issue.title, "", global: false)
    proposed = "#{type}#{scope_suffix}: #{issue.identifier} - #{summary}"

    Prompt.ask("Title for PR for #{issue.identifier} - #{summary}", default: proposed)
  end

  @doc """
  Opens `pr_description_for/2`'s proposed Context/Issue/Solution/Testing/Notes
  template in an editor, returning whatever the user saved.

  Ported from `WhatFor#pr_description_for`. See the moduledoc's "Deliberate
  deviations" section: this always returns the resulting `String.t()`
  directly (never a Ruby-style `Tempfile` handle), and has no fallback for a
  failed editor command (Ruby's `TTY::Editor.open` returning falsy) since
  `LinearCli.CLI.Prompt.edit/2` has no equivalent recoverable failure signal
  to check.

  `editor_opts`, like `ask_or_edit/3`'s, isn't part of Ruby's arity-1
  `pr_description_for(issue)` - it exists purely for non-interactive testing
  and forwards straight through to `LinearCli.CLI.Prompt.edit/2`. Omit it in
  real use.
  """
  @spec pr_description_for(%Linear.Issue{}, keyword()) :: String.t()
  def pr_description_for(issue, editor_opts \\ []) do
    proposed =
      "# Context\n\n#{issue.description}\n\n## Issue\n\n#{issue.identifier}\n\n" <>
        "# Solution\n\n# Testing\n\n# Notes\n\n"

    Prompt.edit(proposed, Keyword.put_new(editor_opts, :format, "md"))
  end

  @doc """
  Infers a Conventional-Commits type prefix (e.g. `"fix"`) from the start of
  `issue.title`, if there is one; otherwise prompts
  (`LinearCli.CLI.Prompt.select/2`) for one from the fixed `PR_TYPES` list.

  Ported from `WhatFor#pr_type_for`. Always returns a `String.t()` - see the
  moduledoc's "Deliberate deviations" section for how this differs from
  Ruby's own type-inconsistent two branches.
  """
  @spec pr_type_for(%Linear.Issue{}) :: String.t()
  def pr_type_for(issue) do
    case Regex.run(@pr_type_prefix_regex, issue.title) do
      [_match, type] -> String.downcase(type)
      nil -> Prompt.select("What type of PR is this?", @pr_type_choices) |> to_string()
    end
  end

  @doc """
  Extracts a Conventional-Commits scope from a leading `"type(scope)"` in
  `title`, if there is one; otherwise asks for one, defaulting to `"none"`.

  Ported from `WhatFor#pr_scope_for`. Ruby's own fallback branch -
  `return nil if scope.empty? && scope == 'none'` - can never actually
  return `nil`: `scope.empty?` and `scope == 'none'` can't both be true at
  once, and `LinearCli.CLI.Prompt.ask/2` (like Ruby's `TTY::Prompt#ask`)
  never returns `""` when a `default:` is given anyway. This is ported
  exactly as-is (the fallback always returns the asked-for string, `"none"`
  on a blank answer) - a faithful port of what reads like dead code in the
  original, not a bug this port introduces or fixes.
  """
  @spec pr_scope_for(String.t()) :: String.t() | nil
  def pr_scope_for(title) do
    case Regex.run(@pr_scope_regex, title) do
      [_match, scope] ->
        String.downcase(scope)

      nil ->
        scope = Prompt.ask("What is the scope of this PR?", default: "none")
        if scope == "" and scope == "none", do: nil, else: scope
    end
  end

  @doc """
  Returns `thing` unchanged if given (and not `"-"`); otherwise asks
  `question` (offering `"-"` to open an editor instead), and if the answer
  is `"-"`, opens one via `editor_for/2`, raising if the editor produced no
  content.

  Ported from `WhatFor#ask_or_edit`. Any `raise` here is a plain
  `RuntimeError`, not Ruby's `SmellsBad` - see the moduledoc's "Deliberate
  deviations" section.

  `editor_opts` isn't part of Ruby's `ask_or_edit(thing, question)` (arity
  2) - it exists purely so this (and everything built on top of it:
  `description_for/1`, `reason_for/2`, `comment_for/2`) can be driven
  non-interactively in tests without mutating the process-global
  `ELIXIR_EDITOR` env var, exactly per `LinearCli.CLI.Prompt`'s own
  moduledoc (e.g. `ask_or_edit(nil, "Description", editor: "echo done >> __FILE__")`).
  Omit it in real use; it forwards straight through to `editor_for/2` /
  `LinearCli.CLI.Prompt.edit/2`.
  """
  @spec ask_or_edit(String.t() | nil, String.t(), keyword()) :: String.t()
  def ask_or_edit(thing, question, editor_opts \\ [])

  def ask_or_edit(thing, question, editor_opts) do
    if thing && thing != "-" do
      thing
    else
      case Prompt.ask("#{question}: ('-' to open an editor)", default: "-") do
        "-" ->
          case editor_for(question, editor_opts) do
            "" -> raise "No content provided for #{question}"
            answer -> answer
          end

        answer ->
          answer
      end
    end
  end

  @doc """
  Opens a blank buffer in an external editor and returns its saved lines,
  chomped and rejoined with the **literal two-character string** `"\\\\n"`
  (a backslash followed by `n` - not a real newline).

  Ported from `WhatFor#editor_for`, whose Ruby body ends with
  `.join('\\\\n')` - a Ruby *single-quoted* string literal, which does not
  interpret `\\n` as a newline escape (only `\\\\` and `\\'` are special
  inside single quotes), so that call joins lines with a literal backslash
  followed by `n`, not `U+000A`. Preserved exactly, as a faithful port of
  what reads like an accidental double-escape in the original, not something
  this port fixes.

  `prefix` is accepted only for signature fidelity with Ruby (which passes
  it through to `Tempfile.open` purely to name the temp file) - it has no
  effect here, since `LinearCli.CLI.Prompt.edit/2`/`Owl.IO.open_in_editor/2`
  has no equivalent temp-file-naming option.

  `opts` forwards straight through to `LinearCli.CLI.Prompt.edit/2` - pass
  `editor: "some non-interactive shell command"` to drive this in tests (see
  `LinearCli.CLI.Prompt`'s own moduledoc). A `:format` of `"md"` is merged in
  by default (matching the only real caller's `.md` suffix) unless `opts`
  overrides it.
  """
  @spec editor_for(String.t() | nil, keyword()) :: String.t()
  def editor_for(prefix \\ nil, opts \\ [])

  def editor_for(_prefix, opts) do
    ""
    |> Prompt.edit(Keyword.put_new(opts, :format, "md"))
    |> String.split(["\r\n", "\n"])
    |> drop_trailing_blank_line()
    |> Enum.join("\\n")
  end

  # `File.readlines` in Ruby doesn't produce a phantom trailing empty
  # element for a file that ends with a newline; `String.split/2` does
  # (a trailing delimiter yields a trailing `""`) - drop it to match.
  defp drop_trailing_blank_line(lines) do
    case List.last(lines) do
      "" -> List.delete_at(lines, -1)
      _ -> lines
    end
  end
end
