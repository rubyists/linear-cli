defmodule Mix.Tasks.Githooks.Install do
  @moduledoc "Activates this repo's githooks/ (conventional-commit enforcement on commit-msg)."
  @shortdoc "Activates the repo's git hooks"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    with {root, 0} <- System.cmd("git", ["rev-parse", "--show-toplevel"], stderr_to_stdout: true),
         root = String.trim(root),
         {_output, 0} <-
           System.cmd("git", ["config", "core.hooksPath", "githooks"],
             cd: root,
             stderr_to_stdout: true
           ) do
      Mix.shell().info("githooks activated (core.hooksPath = githooks)")
    else
      {output, _status} -> Mix.raise("Failed to activate githooks: #{String.trim(output)}")
    end
  end
end
