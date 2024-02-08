# frozen_string_literal: true

require 'semantic_logger'
require 'pry'

module Rubyists
  # Namespace for Linear
  module Linear
    # Namespace for CLI
    module CLI
      Console = Class.new Dry::CLI::Command
      # The Console command
      class Console
        include SemanticLogger::Loggable
        include Rubyists::Linear::CLI::CommonOptions

        desc 'Open a console session'

        def call(**)
          Dir.mktmpdir('.linear-cli-console') do |dir|
            Rubyists::Linear.tmpdir = dir
            Rubyists::Linear.pry
          end
        end

        prepend Rubyists::Linear::CLI::Caller
      end
      register 'console', Console, aliases: %w[pry]
    end
  end
end
