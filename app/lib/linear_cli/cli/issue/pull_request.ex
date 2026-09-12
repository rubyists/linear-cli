defmodule LinearCli.CLI.Issue.PullRequest do
  @moduledoc """
  PR-creation workflow for an already-loaded issue: resolve a title/description
  and shell out to `gh pr create`.

  Extracted from the former `LinearCli.CLI.IssueHelpers`. Ported from
  `Rubyists::Linear::CLI::Issue`
  (vendor/ruby-linear-cli/lib/linear/commands/issue.rb): `create_pr!`,
  `issue_pr`.

  ## Return convention

  `create_pr!/3` returns a `String.t()` (the runner's stdout — typically the
  new PR's URL). `issue_pr/2` always returns `:ok`.

  ## `create_pr!/3`

  Ported from `CLI::Issue#create_pr!`, which shells out to `gh pr create`.
  Ruby branches on whether `body` is a `Tempfile` (`--body-file`) or a
  plain `String` (`--body`); this port's `body` is always a `String.t()`
  (see `LinearCli.CLI.WhatFor.pr_description_for/2`'s own moduledoc note on
  why it never returns a Ruby-style `Tempfile` handle here), so only the
  `--body` shape applies. Takes an injectable `runner` (a `(title, body) ->
  String.t()` function), defaulting to a real `System.cmd/3` call, so tests
  never actually shell out to a real `gh` — the same pattern this codebase
  already uses for `LinearCli.CLI.main/2`'s injectable `halt` and
  `LinearCli.Git`'s injectable `cwd:`.
  """

  alias LinearCli.CLI.{Prompt, WhatFor}
  alias LinearCli.Linear

  @doc """
  Shells out to `gh pr create -a @me --title TITLE --body BODY`, returning
  whatever the command printed to stdout (Ruby's backtick-captured output —
  typically the created PR's URL).

  `runner`, a `(title, body) -> String.t()` function, defaults to a real
  `System.cmd/3` call — pass an override in tests. Ported from
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
  `options[:description]` — note Ruby's own `update_issue` never actually
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
end
