# frozen_string_literal: true

module Rubyists
  module Linear
    # The Cli module is defined in cli.rb and is the top-level namespace for all CLI commands
    module CLI
      # The Team module is the namespace for all team-related commands
      module Team
        include CLI::SubCommands
        # Aliases for Team commands.
        ALIASES = {
          list: %w[ls l],   # aliases for the list command
          team: %w[t teams] # aliases for the main team command itself
        }.freeze
      end
    end
  end
end
