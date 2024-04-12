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

          desc 'List issues'
          example [
            '            # List your issues',
            '--no-mine   # List The most recent 100 issues',
            '-u          # List unassigned issues',
            '-fu         # List unassigned issues with full details',
            'CRY-123     # Show issue CRY-123'
          ]
          argument :ids, type: :array, default: [], desc: 'Issue IDs to list'
          option :mine, type: :boolean, default: true, desc: 'Only show my issues'
          option :unassigned, aliases: ['-u'], type: :boolean, default: false, desc: 'Show unassigned issues only'
          option :team, aliases: ['-t'], type: :string, desc: 'Show issues for only this team'
          option :full, type: :boolean, aliases: ['-f'], default: false, desc: 'Show full issue details'

          def call(ids:, **options)
            logger.debug 'Listing issues'
            return display(issues_for(options), options) if ids.empty?

            display issues_for(options.merge(ids:)), options
          end

          def filters_for(options)
            filter = {}
            filter[:assignee] = { isMe: { eq: true } } if options[:mine]
            filter[:assignee] = { null: true } if options[:unassigned]
            filter[:team] = { key: { eq: options[:team] } } if options[:team]
            filter
          end

          def issues_for(options)
            logger.debug('Fetching issues', options:)
            return options[:ids].map { |id| Rubyists::Linear::Issue.find(id.upcase) } if options[:ids]

            Rubyists::Linear::Issue.all filter: filters_for(options)
          end
        end
      end
    end
  end
end
