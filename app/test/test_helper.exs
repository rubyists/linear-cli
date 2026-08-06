# A fixed dummy key, set once for the whole (async) suite. LINEAR_API_KEY is a
# real OS env var, not per-process state - mutating it per-test in async: true
# modules races across files. The one test that needs it *unset*
# (LinearCli.ApiTest) manages it itself and runs async: false.
System.put_env("LINEAR_API_KEY", "test-key")

ExUnit.start()
