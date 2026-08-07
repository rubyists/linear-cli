import Config

config :linear_cli, :ash_domains, [LinearCli.Linear]

# Which repo `mix ecto.*` tasks target locally - a dev/ops convenience
# selector only. Distinct from LinearCli.ObanRepo's *runtime* dispatch
# (see its moduledoc) that the shipped app itself actually uses - this one
# only affects mix task invocations, never the running app.
config :linear_cli,
  ecto_repos: [
    case System.get_env("LINEAR_CLI_DB_ADAPTER", "sqlite") do
      "sqlite" ->
        LinearCli.ObanRepo.Sqlite

      "postgres" ->
        LinearCli.ObanRepo.Postgres

      other ->
        raise "LINEAR_CLI_DB_ADAPTER must be \"sqlite\" or \"postgres\", got: #{inspect(other)}"
    end
  ]

# Only started in daemon run mode (see LinearCli.Application's
# LINEAR_CLI_DAEMON gate) - the interactive CLI never boots this. @monthly
# is midnight on the 1st (Oban.Plugins.Cron's documented alias). `notifier:
# Oban.Notifiers.PG` works against any backing store (it relays over
# distributed Erlang process groups, never touching the database), so it
# doesn't need to switch with the engine/adapter the way they do. No
# `repo:`/`engine:` here - LinearCli.Application merges those in at boot,
# from LinearCli.ObanRepo's runtime pick.
config :linear_cli, Oban,
  notifier: Oban.Notifiers.PG,
  queues: [default: 10],
  plugins: [{Oban.Plugins.Cron, crontab: [{"@monthly", LinearCli.Rollover.Worker}]}]

# The prefix used to name each month's rollover project, e.g. "PAYMENTS
# SWAT" -> "PAYMENTS SWAT August 2026". See LinearCli.Rollover.
config :linear_cli, :rollover, prefix: "PAYMENTS SWAT"

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  many_to_many_destroy_destination_on_match?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

import_config "#{config_env()}.exs"
