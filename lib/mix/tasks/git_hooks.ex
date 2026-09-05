defmodule Mix.Tasks.GitHooks do
  @shortdoc "Installs this repo's pre-commit, commit-msg, and pre-push hooks"

  @moduledoc """
  #{@shortdoc}.

      mix git_hooks

  Sets `core.hooksPath` to `git-hooks/`: its `pre-commit` hook prevents direct
  commits to `main` and runs `mix precommit`; its `commit-msg` hook enforces
  Conventional Commits on each commit subject; and its `pre-push` hook validates
  all commit subjects introduced by the push before running Hex's dependency
  security audit.
  This is idempotent and safe to run repeatedly: setting the same Git config
  value twice is a no-op. Wired into `mix setup` - see that task.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    run(argv, &Shell.run!/3)
    Mix.shell().info("==> Git hooks installed (core.hooksPath = git-hooks)")
    :ok
  end

  @doc false
  def run([], shell) do
    shell.("git", ["config", "core.hooksPath", "git-hooks"], [])
    :ok
  end

  def run(_argv, _shell) do
    Mix.raise("Usage: mix git_hooks")
  end
end
