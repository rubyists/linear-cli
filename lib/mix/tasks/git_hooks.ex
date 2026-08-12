defmodule Mix.Tasks.GitHooks do
  @shortdoc "Installs this repo's git hooks (commit-msg, pre-push - Conventional Commits)"

  @moduledoc """
  #{@shortdoc}.

      mix git_hooks

  Sets `core.hooksPath` to `githooks/` (this repo's own `commit-msg` and
  `pre-push` hooks, both enforcing Conventional Commits via
  `ci/validate_conventional_commit.sh`/`ci/conventional_commits.sh`) -
  the same one-line `git config` this repo's docs already told you to run
  by hand, just idempotent and easy to re-run. Safe to run repeatedly:
  setting the same git config value twice is a no-op. Wired into
  `mix setup` - see that task.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(_argv) do
    Shell.run!("git", ["config", "core.hooksPath", "githooks"])
    Mix.shell().info("==> Git hooks installed (core.hooksPath = githooks)")
    :ok
  end
end
