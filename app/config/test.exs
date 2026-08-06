import Config
config :ash, policies: [show_policy_breakdowns?: true]
config :linear_cli, req_options: [plug: {Req.Test, LinearCli.Api}]
