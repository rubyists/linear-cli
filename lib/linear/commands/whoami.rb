# frozen_string_literal: true

require 'semantic_logger'

module Rubyists
  # Namespace for Linear
  module Linear
    M :user
    # Namespace for CLI
    module CLI
      WhoAmI = Class.new Dry::CLI::Command
      # The WhoAmI command
      class WhoAmI
        include SemanticLogger::Loggable
        include Rubyists::Linear::CLI::CommonOptions

        desc 'Get your own user info'

        option :teams, aliases: ['-t'], type: :boolean, default: false, desc: 'Show teams'

        def call(**options)
          logger.debug 'Getting user info'
          display Rubyists::Linear::User.me(teams: options[:teams]), options
        end

        prepend Rubyists::Linear::CLI::Caller
      end
      register 'whoami', WhoAmI, aliases: %w[me w who whodat]
    end
  end
end
