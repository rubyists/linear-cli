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

ExUnit.start()
