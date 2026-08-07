import Config
config :ash, policies: [show_policy_breakdowns?: true]

# LinearCli.ObanRepo's connection details live in config/runtime.exs - they
# need to be boot-time, not build-time, so a daemon restart (not a rebuild)
# picks up new credentials/host. See that file and ObanRepo's moduledoc.
