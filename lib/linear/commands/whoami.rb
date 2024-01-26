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

        def call(**options)
          logger.debug 'Getting user info'
          display Rubyists::Linear::User.me, options
        end

        prepend Rubyists::Linear::CLI::Caller
      end
      register 'whoami', WhoAmI
    end
  end
end
