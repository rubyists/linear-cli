defmodule Mix.Tasks.Setup do
  @shortdoc "Sets up this repo for development"

  @moduledoc """
  #{@shortdoc}.

      mix setup

  Runs every one-time/idempotent setup step this repo needs. Currently
  just `mix git_hooks` - expected to grow (e.g. app/'s own `mix deps.get`)
  as more repo-management tasks land here.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("git_hooks")
    :ok
  end
end
