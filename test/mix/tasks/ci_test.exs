defmodule Mix.Tasks.CiTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ci

  test "runs all quality gate steps in order" do
    caller = self()

    shell = fn cmd, args, opts ->
      send(caller, {:run, cmd, args, opts})
      :ok
    end

    assert :ok = Ci.run([], shell)

    assert_receive {:run, "mix", ["deps.get"], [cd: "app"]}
    assert_receive {:run, "mix", ["format", "--check-formatted"], [cd: "app"]}
    assert_receive {:run, "mix", ["usage_rules.sync", "--check"], [cd: "app"]}
    assert_receive {:run, "mix", ["test"], [cd: "app"]}
  end
end
