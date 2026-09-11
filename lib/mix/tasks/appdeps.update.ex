defmodule Mix.Tasks.Appdeps.Update do
  @shortdoc "Updates one or more app dependencies"

  @moduledoc """
  #{@shortdoc}.

      mix appdeps.update DEP [DEP ...]

  Runs `mix deps.update` for the named dependencies from the `app/` project.
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
    shell.("mix", ["deps.update" | dependencies], cd: "app")
    :ok
  end
end
