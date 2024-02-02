# frozen_string_literal: true

require 'semantic_logger'

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue, :user, :label
    # Namespace for CLI
    module CLI
      module Issue
        Create = Class.new Dry::CLI::Command
        # The Create class is a Dry::CLI::Command to create a new issue
        class Create
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions
          include Rubyists::Linear::CLI::Issue # for #gimme_da_issue and other methods
          desc 'Create a  new issue'
          option :title, type: :string, aliases: ['-t'], desc: 'Issue Title'
          option :team, type: :string, aliases: ['-T'], desc: 'Team Identifier'
          option :description, type: :string, aliases: ['-d'], desc: 'Issue Description'
          option :labels, type: :array, aliases: ['-l'], desc: 'Labels for the issue (Comma separated list)'

          def call(**options)
            logger.debug('Creating issue', options:)
            issue = make_da_issue!(**options)
            logger.debug('Issue created', issue:)
          end
        end
      end
    end
  end
end
