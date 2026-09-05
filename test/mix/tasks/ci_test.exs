defmodule Mix.Tasks.CiTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Ci

  test "bootstraps deps, validates, runs precommit checks, then CI-only checks" do
    caller = self()

    shell = fn cmd, args, opts ->
      send(caller, {:run, cmd, args, opts})
      :ok
    end

    assert :ok = Ci.run([], shell)

    # Bootstrap
    assert_received {:run, "mix", ["deps.get"], [cd: "app"]}
    # Metadata guards (fast failures before the expensive steps)
    assert_received {:run, "./ci/validate_pull_request_title.sh", [], []}
    assert_received {:run, "./ci/validate_commit_range.sh", [], []}
    # All precommit local checks are present (mix precommit ⊂ mix ci)
    assert_received {:run, "mix", ["format", "--check-formatted"], []}
    assert_received {:run, "mix", ["test"], []}
    assert_received {:run, "mix", ["format", "--check-formatted"], [cd: "app"]}
    assert_received {:run, "mix", ["credo", "--strict"], [cd: "app"]}
    assert_received {:run, "mix", ["test", "--exclude", "ci_only"], [cd: "app"]}
    # CI-only audits, followed by the unfiltered app suite.
    assert_received {:run, "mix", ["hex.audit"], [cd: "app"]}
    assert_received {:run, "mix", ["deps.audit"], [cd: "app"]}
    assert_received {:run, "mix", ["usage_rules.sync", "--check"], [cd: "app"]}
    assert_received {:run, "mix", ["test"], [cd: "app"]}
    refute_received {:run, "mix", ["test", "--only", "ci_only"], _}
  end

  test "rejects arguments" do
    assert_raise Mix.Error, "Usage: mix ci", fn ->
      Ci.run(["unexpected"], fn _, _, _ -> :ok end)
    end
  end
end
