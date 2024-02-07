# frozen_string_literal: true

require 'semantic_logger'

module Rubyists
  # Namespace for Linear
  module Linear
    M :user
    # Namespace for CLI
    module CLI
      Version = Class.new Dry::CLI::Command
      # The Version command
      class Version
        include SemanticLogger::Loggable
        include Rubyists::Linear::CLI::CommonOptions

        desc 'Show version'

        def call(**)
          logger.debug 'Version called'
          TTY::Prompt.new.say Rubyists::Linear::VERSION
        end
      end
      register 'version', Version, aliases: %w[v]
    end
  end
end
