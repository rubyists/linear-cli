defmodule Mix.Tasks.Precommit do
  @shortdoc "Runs every local and CI validation for this repository"

  @moduledoc """
  #{@shortdoc}.

      mix precommit

  This is the single validation entrypoint for developers, Git hooks, and
  GitHub Actions. Cheap metadata guards run first so an invalid pull request
  title or commit subject fails before dependency setup and the test suite:

    1. `ci/validate_pull_request_title.sh` — require a Conventional Commits
       pull request title when `PULL_REQUEST_TITLE_REQUIRED=true`
    2. `ci/validate_commit_range.sh` — validate every commit since the branch
       diverged from its base
    3. `mix deps.get` — ensure app dependencies are present
    4. `mix hex.audit` — reject retired or vulnerable Hex packages
    5. `mix deps.audit` — scan dependencies for known security advisories
    6. `mix format --check-formatted` — check formatting
    7. `mix credo --strict` — run static analysis
    8. `mix usage_rules.sync --check` — catch usage-rule drift after dep bumps
    9. `mix test` — run the app test suite

  Pull request metadata does not exist before a pull request is opened, so
  local runs skip only the title guard. GitHub Actions sets both
  `PULL_REQUEST_TITLE_REQUIRED=true` and `PULL_REQUEST_TITLE` from the event;
  a missing, empty, or non-conventional title then fails this task. Commit
  subjects are always validated.

  All Mix quality steps run inside `app/`.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    run(argv, &Shell.run!/3)
  end

  @doc false
  def run([], shell) do
    shell.("./ci/validate_pull_request_title.sh", [], [])
    shell.("./ci/validate_commit_range.sh", [], [])
    shell.("mix", ["deps.get"], cd: "app")
    shell.("mix", ["hex.audit"], cd: "app")
    shell.("mix", ["deps.audit"], cd: "app")
    shell.("mix", ["format", "--check-formatted"], cd: "app")
    shell.("mix", ["credo", "--strict"], cd: "app")
    shell.("mix", ["usage_rules.sync", "--check"], cd: "app")
    shell.("mix", ["test"], cd: "app")
    :ok
  end

  def run(_argv, _shell) do
    Mix.raise("Usage: mix precommit")
  end
end
