import Config
config :ash, policies: [show_policy_breakdowns?: true]
config :linear_cli, req_options: [plug: {Req.Test, LinearCli.Api}, retry: false]

# LinearCli.ObanRepo's connection details live in config/runtime.exs - see
# that file and ObanRepo's moduledoc. Doesn't matter functionally today
# (LinearCli.ObanRepo is never started in tests - LINEAR_CLI_DAEMON isn't
# set), but has to be shaped correctly for whichever adapter got compiled in.
