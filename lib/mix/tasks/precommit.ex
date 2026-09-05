defmodule Mix.Tasks.Precommit do
  @shortdoc "Fast local quality gate (format, static analysis, unit tests)"

  @moduledoc """
  #{@shortdoc}.

      mix precommit

  A fast, self-contained command designed for frequent developer use: between
  edits, before committing, and as the pre-push hook target. On a warm checkout
  with dependencies already installed, it completes in under five seconds.

  It requires no network access, credentials, containers, or external services.
  Run `mix deps.get` inside `app/` once after cloning or after updating
  `app/mix.lock`, then run `mix precommit` as often as you like.

  Steps:

    1. `mix format --check-formatted` — check root project formatting
    2. `mix test` — run the root project test suite (validator and task tests)
    3. `mix format --check-formatted` — check app formatting
    4. `mix credo --strict` — run static analysis on the app
    5. `mix test --exclude ci_only` — run the app unit test suite

  Steps 1-2 run from the repo root; steps 3-5 run inside `app/`.
  App tests tagged `@moduletag :ci_only` are excluded only from this local
  gate. `mix ci` runs the complete app suite without a test-selection flag.

  For the complete integration gate — dependency bootstrap and audits,
  PR-title and commit-range validation, and CI-classified tests — use `mix ci`.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    run(argv, &Shell.run!/3)
  end

  @doc false
  def run([], shell) do
    shell.("mix", ["format", "--check-formatted"], [])
    shell.("mix", ["test"], [])
    shell.("mix", ["format", "--check-formatted"], cd: "app")
    shell.("mix", ["credo", "--strict"], cd: "app")
    shell.("mix", ["test", "--exclude", "ci_only"], cd: "app")
    :ok
  end

  def run(_argv, _shell) do
    Mix.raise("Usage: mix precommit")
  end
end
