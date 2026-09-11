defmodule Mix.Tasks.Appdeps.UpdateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Appdeps.Update

  test "updates the named dependencies from app" do
    caller = self()

    shell = fn cmd, args, opts ->
      send(caller, {:run, cmd, args, opts})
      :ok
    end

    assert :ok = Update.run(["ash", "oban"], shell)
    assert_received {:run, "mix", ["deps.update", "ash", "oban"], [cd: "app"]}
  end

  test "requires at least one dependency" do
    assert_raise Mix.Error, "Usage: mix appdeps.update DEP [DEP ...]", fn ->
      Update.run([], fn _, _, _ -> :ok end)
    end
  end
end
