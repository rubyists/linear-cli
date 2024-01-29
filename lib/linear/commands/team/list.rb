# frozen_string_literal: true

require 'semantic_logger'

module Rubyists
  # Namespace for Linear
  module Linear
    M :team, :issue
    # Namespace for CLI
    module CLI
      module Team
        List = Class.new Dry::CLI::Command
        # The List class is a Dry::CLI::Command that lists issues
        class List
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions

          option :mine, type: :boolean, default: true, desc: 'Only show my issues'

          def call(**options)
            logger.debug 'Listing teams'
            display teams_for(options), options
          end

          def teams_for(options)
            return Rubyists::Linear::Team.mine if options[:mine]

            Rubyists::Linear::Team.all
          end

          prepend Rubyists::Linear::CLI::Caller
        end
      end

      register 'team', aliases: %w[t] do |team|
        team.register 'ls', Team::List
      end
    end
  end
end
