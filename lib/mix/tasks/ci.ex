defmodule Mix.Tasks.Ci do
  @shortdoc "Runs the complete quality gate against app/"

  @moduledoc """
  #{@shortdoc}.

      mix ci

  Runs every check `.github/workflows/ci.yaml`'s `test` job runs on a pull
  request, in the same order, so a green `mix ci` locally predicts a green
  CI run — and CI itself calls this task, so there's one place to fix if
  either ever breaks:

    1. `mix deps.get` — ensure deps are present
    2. `mix format --check-formatted` — code is formatted
    3. `mix usage_rules.sync --check` — usage rules are in sync with deps
       (catches drift introduced by a dep bump without re-running the sync;
       see #79)
    4. `mix test` — all tests pass

  All steps run inside `app/`.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    run(argv, &Shell.run!/3)
  end

  @doc false
  def run(_argv, shell) do
    shell.("mix", ["deps.get"], cd: "app")
    shell.("mix", ["format", "--check-formatted"], cd: "app")
    shell.("mix", ["usage_rules.sync", "--check"], cd: "app")
    shell.("mix", ["test"], cd: "app")
    :ok
  end
end
