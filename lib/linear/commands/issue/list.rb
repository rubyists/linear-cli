# frozen_string_literal: true

require 'semantic_logger'

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue
    M :user
    # Namespace for CLI
    module CLI
      module Issue
        List = Class.new Dry::CLI::Command
        # The List class is a Dry::CLI::Command that lists issues
        class List
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions

          option :mine, type: :boolean, default: true, desc: 'Only show my issues'
          option :unassigned, aliases: ['-u'], type: :boolean, default: false, desc: 'Show unassigned issues only'
          option :full, type: :boolean, aliases: ['-f'], default: false, desc: 'Show full issue details'

          def call(**options)
            logger.debug 'Listing issues'

            display issues_for(options), options
          end

          def issues_for(options)
            logger.debug('Fetching issues', options:)
            return Rubyists::Linear::Issue.all(filter: { assignee: { null: true } }) if options[:unassigned]
            return Rubyists::Linear::User.me.issues if options[:mine]

            Rubyists::Linear::Issue.all
          end
        end
      end
    end
  end
end
