# A fixed dummy key, set once for the whole (async) suite. LINEAR_API_KEY is a
# real OS env var, not per-process state - mutating it per-test in async: true
# modules races across files. The one test that needs it *unset*
# (LinearCli.ApiTest) manages it itself and runs async: false.
System.put_env("LINEAR_API_KEY", "test-key")

# Owl (LinearCli.CLI.Prompt) renders ANSI color codes via IO.ANSI.format/1,
# which strips them unless ANSI is enabled - normally auto-detected from
# whether stdout is a tty, which it isn't under `mix test`. Force it on once,
# same as Owl's own test suite does (vendor/owl/test/test_helper.exs), so
# LinearCli.CLI.PromptTest can assert on the actual colored output. This is
# an Application env, not an OS env var, and is set once here before
# ExUnit.start() - not per-test - so it doesn't reintroduce the
# LINEAR_API_KEY-style race.
Application.put_env(:elixir, :ansi_enabled, true)

# LinearCli.Profiles opens/closes its own connection per call rather than
# holding one open for the whole suite (see its moduledoc), so its sqlite
# file at :profiles_db_path outlives any single `mix test` invocation on
# disk. Without this, a stray active profile left behind by an earlier run
# would leak into every other test that touches issue_list/make_da_issue!
# but isn't itself aware of profiles - a suite that isn't deterministic
# against its own previous runs. Individual profile-aware test modules
# (LinearCli.ProfilesTest, LinearCli.CLI.ProfileDefaultsTest) still delete
# it again in their own `setup`, since it comes back the moment any test
# creates a profile.
Application.fetch_env!(:linear_cli, :profiles_db_path) |> File.rm()

# Tests tagged @moduletag :ci_only are excluded from the local gate (mix
# precommit). They run only through mix ci's --only ci_only step.
ExUnit.start(exclude: [:ci_only])
