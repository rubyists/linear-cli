defmodule Mix.Tasks.Appdeps.Update do
  @shortdoc "Updates one or more app dependencies"

  @moduledoc """
  #{@shortdoc}.

      mix appdeps.update DEP [DEP ...]

  Checks that CI uses mise's pinned toolchain, runs `mix deps.update` for the
  named dependencies from the `app/` project, then runs the full `mix ci` gate.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    run(argv, &Shell.run!/3)
  end

  @doc false
  def run([], _shell) do
    Mix.raise("Usage: mix appdeps.update DEP [DEP ...]")
  end

  def run(dependencies, shell) do
    Mix.Tasks.Toolchain.Check.run([])
    shell.("mix", ["deps.update" | dependencies], cd: "app")
    Mix.Tasks.Ci.run([], shell)
    :ok
  end
end
