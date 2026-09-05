defmodule Mix.Tasks.PrecommitTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Precommit

  test "runs metadata guards before all quality gate steps" do
    caller = self()

    shell = fn cmd, args, opts ->
      send(caller, {:run, cmd, args, opts})
      :ok
    end

    assert :ok = Precommit.run([], shell)

    assert_receive {:run, "./ci/validate_pull_request_title.sh", [], []}
    assert_receive {:run, "./ci/validate_commit_range.sh", [], []}
    assert_receive {:run, "mix", ["format", "--check-formatted"], []}
    assert_receive {:run, "mix", ["test"], []}
    assert_receive {:run, "mix", ["deps.get"], [cd: "app"]}
    assert_receive {:run, "mix", ["hex.audit"], [cd: "app"]}
    assert_receive {:run, "mix", ["deps.audit"], [cd: "app"]}
    assert_receive {:run, "mix", ["format", "--check-formatted"], [cd: "app"]}
    assert_receive {:run, "mix", ["credo", "--strict"], [cd: "app"]}
    assert_receive {:run, "mix", ["usage_rules.sync", "--check"], [cd: "app"]}
    assert_receive {:run, "mix", ["test"], [cd: "app"]}
  end

  test "rejects arguments" do
    assert_raise Mix.Error, "Usage: mix precommit", fn ->
      Precommit.run(["unexpected"], fn _, _, _ -> :ok end)
    end
  end
end
