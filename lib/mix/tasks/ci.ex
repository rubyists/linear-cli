defmodule Mix.Tasks.Ci do
  @shortdoc "Complete integration gate: local checks plus CI-only audits and validation"

  @moduledoc """
  #{@shortdoc}.

      mix ci

  The canonical pull-request and merge gate, and the command GitHub Actions
  invokes. It bootstraps dependencies, runs fast metadata guards, runs the full
  local gate, then performs CI-only checks that may use the network, PR
  metadata, or advisory services.

  Steps:

    1. `mix deps.get` — ensure app dependencies are installed
    2. `ci/validate_pull_request_title.sh` — require a Conventional Commits PR
       title when `PULL_REQUEST_TITLE_REQUIRED=true`
    3. `ci/validate_commit_range.sh` — validate every commit since the branch
       diverged from its base
    4. `mix precommit` — the fast local gate (format, static analysis, unit tests)
    5. `mix hex.audit` — reject retired or vulnerable Hex packages
    6. `mix deps.audit` — scan dependencies for known security advisories
    7. `mix usage_rules.sync --check` — catch usage-rule drift after dep bumps
    8. `mix test` — run the complete app test suite, including CI-classified tests

  Step 1 and steps 5-8 run inside `app/`. Steps 2-3 run from the repo root.
  Step 4 expands to all of `mix precommit`'s steps in place.

  Every check in `mix precommit` also runs through `mix ci`. The relationship
  is:

      mix precommit  ⊂  mix ci

  Pull request metadata does not exist before a pull request is opened, so
  local runs of `mix ci` skip only the title guard. GitHub Actions sets both
  `PULL_REQUEST_TITLE_REQUIRED=true` and `PULL_REQUEST_TITLE` from the event;
  a missing, empty, or non-conventional title then fails step 2. Commit subjects
  are always validated in step 3.

  For the fast local gate only (no network, no CI metadata), use `mix precommit`.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    run(argv, &Shell.run!/3)
  end

  @doc false
  def run([], shell) do
    shell.("mix", ["deps.get"], cd: "app")
    shell.("./ci/validate_pull_request_title.sh", [], [])
    shell.("./ci/validate_commit_range.sh", [], [])
    Mix.Tasks.Precommit.run([], shell)
    shell.("mix", ["hex.audit"], cd: "app")
    shell.("mix", ["deps.audit"], cd: "app")
    shell.("mix", ["usage_rules.sync", "--check"], cd: "app")
    shell.("mix", ["test"], cd: "app")
    :ok
  end

  def run(_argv, _shell) do
    Mix.raise("Usage: mix ci")
  end
end
