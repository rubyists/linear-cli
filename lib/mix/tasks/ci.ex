defmodule Mix.Tasks.Ci do
  @shortdoc "Compatibility alias for mix precommit"

  @moduledoc """
  #{@shortdoc}.

      mix ci

  Delegates to `Mix.Tasks.Precommit`, which is the canonical full-repository
  quality gate. Kept for backwards compatibility with scripts and CI
  configurations that call `mix ci` directly.

  See `mix help precommit` for the complete step list.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Tasks.Precommit.run(argv)
  end

  @doc false
  def run(argv, shell) do
    Mix.Tasks.Precommit.run(argv, shell)
  end
end
