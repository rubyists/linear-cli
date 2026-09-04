defmodule Mix.Tasks.GitHooksTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.GitHooks

  test "points core.hooksPath at the repository-owned hooks" do
    caller = self()

    shell = fn cmd, args, opts ->
      send(caller, {:run, cmd, args, opts})
      :ok
    end

    assert :ok = GitHooks.run([], shell)

    assert_receive {:run, "git", ["config", "core.hooksPath", "git-hooks"], []}
  end

  test "rejects arguments" do
    assert_raise Mix.Error, "Usage: mix git_hooks", fn ->
      GitHooks.run(["unexpected"], fn _, _, _ -> :ok end)
    end
  end
end
