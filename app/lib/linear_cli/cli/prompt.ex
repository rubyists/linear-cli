defmodule LinearCli.CLI.Prompt do
  @moduledoc """
  Interactive-prompt primitives, wrapping the vendored/hex `owl` dependency
  (see `app/deps/owl`, source also mirrored at `vendor/owl`) to replace
  Ruby's `TTY::Prompt`/`TTY::Editor`.

  Ported from `Rubyists::Linear::CLI.prompt`
  (vendor/ruby-linear-cli/lib/linear/cli.rb) - every call site under
  vendor/ruby-linear-cli/lib/linear/cli/what_for.rb,
  vendor/ruby-linear-cli/lib/linear/cli/projects.rb,
  vendor/ruby-linear-cli/lib/linear/cli/sub_commands.rb, and
  vendor/ruby-linear-cli/lib/linear/commands/**/*.rb was inventoried to
  arrive at this module's surface. Colors for `ok/1`/`warn/1`/`say/1` are
  taken directly from the real `TTY::Prompt#ok`/`#warn`/`#say` source
  (`tty-prompt-0.23.1/lib/tty/prompt.rb`, installed under
  `~/.local/share/mise/installs/ruby/*/lib/ruby/gems/*/gems/`): `ok` is
  `color: :green`, `warn` is `color: :yellow`, `say` has no color. Likewise
  `yes?/1` mirrors `TTY::Prompt#yes?`, which merges `default: true` (i.e. a
  bare Enter answers "yes") - the opposite of `Owl.IO.confirm/1`'s own
  built-in default of `false`, so that default is overridden below.

  ## Testing without a real terminal

  `ok/1`, `warn/1`, and `say/1` only ever write to stdout, so, like every
  other command output in this codebase, they're already covered by
  `ExUnit.CaptureIO.capture_io/1` (see `LinearCli.CLITest`).

  `ask/2`, `yes?/1`, `select/2`, and `multi_select/2` delegate straight to
  `Owl.IO.input/1`, `Owl.IO.confirm/1`, `Owl.IO.select/2`, and
  `Owl.IO.multiselect/2`. None of those Owl functions accept an explicit I/O
  device for *reading* input - they read via `IO.gets/1`, which resolves
  through the *calling process'* group leader. `ExUnit.CaptureIO.capture_io/2`
  swaps that process' group leader for a `StringIO` for the duration of its
  callback and lets you feed scripted input through the `:input` option -
  this is exactly the mechanism Owl's own test suite uses to drive these same
  functions (see `Owl.IOTest` in `vendor/owl/test/owl/io_test.exs`, e.g.
  `capture_io([input: "2\\n"], fn -> Owl.IO.select(...) end)`). Drive every
  prompt in this module, and anything built on top of it (e.g.
  `LinearCli.CLI.Projects`), the same way:

      import ExUnit.CaptureIO

      assert capture_io([input: "2\\n"], fn ->
               assert Prompt.select("Pick one", [{"a", :a}, {"b", :b}]) == :b
             end) =~ "Pick one"

      assert capture_io([input: "y\\n"], fn ->
               assert Prompt.yes?("Continue?")
             end)

      assert capture_io([input: "\\n"], fn ->
               assert Prompt.ask("Title", default: "untitled") == "untitled"
             end)

  There is deliberately no injectable io-device parameter anywhere on this
  module's own API - the injection point is the group leader that
  `ExUnit.CaptureIO` already owns, one level below this module (inside Owl).
  Any other module that calls into `LinearCli.CLI.Prompt` is testable the
  same way, with no plumbing of its own required - it's the same pattern
  `LinearCli.CLI.main/2` uses an injectable `halt` function for (different
  mechanism, same goal: keep side effects swappable in tests).

  `edit/2` is the one function here that doesn't touch stdin/stdout at all -
  it shells out to an external editor via `Owl.IO.open_in_editor/2`, so it
  can't be driven with `capture_io`. Drive it instead with the `:editor`
  option, forwarded straight through to `Owl.IO.open_in_editor/2` - pass a
  shell command that edits the temp file non-interactively, e.g.
  `editor: "echo 'new data' >> __FILE__"` (`Owl.IO.open_in_editor/2`'s own
  test in `vendor/owl/test/owl/io_test.exs` does exactly this). Passing
  `:editor` explicitly per call, rather than mutating the process-global
  `ELIXIR_EDITOR` env var, avoids the exact per-test-env-var race class
  called out for `LINEAR_API_KEY` in `app/test/test_helper.exs`.
  """

  @doc """
  Prints `message` as a success/confirmation line, in green.

  Ported from `TTY::Prompt#ok`.
  """
  @spec ok(Owl.Data.t()) :: :ok
  def ok(message), do: Owl.IO.puts(Owl.Data.tag(message, :green))

  @doc """
  Prints `message` as a warning line, in yellow.

  Ported from `TTY::Prompt#warn`.
  """
  @spec warn(Owl.Data.t()) :: :ok
  def warn(message), do: Owl.IO.puts(Owl.Data.tag(message, :yellow))

  @doc """
  Prints `message` plainly, with no color.

  Ported from `TTY::Prompt#say`.
  """
  @spec say(Owl.Data.t()) :: :ok
  def say(message), do: Owl.IO.puts(message)

  @doc """
  Prompts for a free-text line, returning `opts[:default]` (`nil` unless
  given) when the user answers with a blank line.

  Ported from `TTY::Prompt#ask(msg, default:)`, e.g.
  `prompt.ask("\#{question}: ('-' to open an editor)", default: '-')` in
  `Rubyists::Linear::CLI::WhatFor#ask_or_edit`.
  """
  @spec ask(Owl.Data.t(), keyword()) :: String.t() | nil | any()
  def ask(message, opts \\ []) do
    default = Keyword.get(opts, :default)

    case Owl.IO.input(label: message, optional: true, cast: :string) do
      nil -> default
      value -> value
    end
  end

  @doc """
  Asks a yes/no question, defaulting to `true` (an empty answer means
  "yes") - matching `TTY::Prompt#yes?`, not `Owl.IO.confirm/1`'s own default
  of `false`.

  Ported from `TTY::Prompt#yes?`, e.g.
  `prompt.yes?('Do you want to take this issue?')` in
  `Rubyists::Linear::CLI::Issue::Create`.
  """
  @spec yes?(Owl.Data.t()) :: boolean()
  def yes?(message), do: Owl.IO.confirm(message: message, default: true)

  @doc """
  Prompts for a single choice from an ordered `[{label, value}]` list,
  returning the chosen `value`.

  Ported from `TTY::Prompt#select(msg, name_to_value_hash)`, e.g.
  `prompt.select('Choose a team', teams.to_h { |t| [t.name, t.key] })` in
  `Rubyists::Linear::CLI::SubCommands#ask_for_team`. Ruby hashes preserve
  insertion order, which is why this takes an ordered list of pairs rather
  than a `Map` (whose enumeration order isn't part of its contract).
  """
  @spec select(Owl.Data.t(), [{Owl.Data.t(), value}, ...]) :: value when value: var
  def select(message, [_ | _] = choices) do
    {_label, value} = Owl.IO.select(choices, label: message, render_as: &elem(&1, 0))
    value
  end

  @doc """
  Prompts for zero or more choices from an ordered `[{label, value}]` list,
  returning the chosen `value`s.

  Ported from `TTY::Prompt#multi_select(msg, name_to_value_hash)`, e.g.
  `prompt.multi_select('Labels:', team.labels.to_h { |t| [t.name, t] })` in
  `Rubyists::Linear::CLI::WhatFor#labels_for`.
  """
  @spec multi_select(Owl.Data.t(), [{Owl.Data.t(), value}, ...]) :: [value] when value: var
  def multi_select(message, [_ | _] = choices) do
    choices
    |> Owl.IO.multiselect(label: message, render_as: &elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Opens `text` in an external editor, returning the saved content once the
  editor exits.

  Ported from `TTY::Editor.open`, as used by
  `Rubyists::Linear::CLI::WhatFor#editor_for`/`#pr_description_for`.

  `opts` is forwarded verbatim to `Owl.IO.open_in_editor/2` - pass
  `editor: "some shell command"` to override `$ELIXIR_EDITOR` (also the hook
  tests use to drive this deterministically, see the moduledoc), and/or
  `format: "md"` to give the temp file a matching extension.
  """
  @spec edit(iodata(), String.t() | keyword()) :: String.t()
  def edit(text, opts \\ []), do: Owl.IO.open_in_editor(text, opts)
end
