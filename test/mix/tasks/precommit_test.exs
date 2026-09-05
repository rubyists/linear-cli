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

    assert_received {:run, "./ci/validate_pull_request_title.sh", [], []}
    assert_received {:run, "./ci/validate_commit_range.sh", [], []}
    assert_received {:run, "mix", ["format", "--check-formatted"], []}
    assert_received {:run, "mix", ["test"], []}
    assert_received {:run, "mix", ["deps.get"], [cd: "app"]}
    assert_received {:run, "mix", ["hex.audit"], [cd: "app"]}
    assert_received {:run, "mix", ["deps.audit"], [cd: "app"]}
    assert_received {:run, "mix", ["format", "--check-formatted"], [cd: "app"]}
    assert_received {:run, "mix", ["credo", "--strict"], [cd: "app"]}
    assert_received {:run, "mix", ["usage_rules.sync", "--check"], [cd: "app"]}
    assert_received {:run, "mix", ["test"], [cd: "app"]}
  end

  test "rejects arguments" do
    assert_raise Mix.Error, "Usage: mix precommit", fn ->
      Precommit.run(["unexpected"], fn _, _, _ -> :ok end)
    end
  end
end
