# frozen_string_literal: true

require 'semantic_logger'
require 'git'
require_relative '../issue'

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue, :user, :label
    # Namespace for CLI
    module CLI
      module Issue
        Update = Class.new Dry::CLI::Command
        # The Update class is a Dry::CLI::Command to update an issue
        class Update
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions
          include Rubyists::Linear::CLI::Issue # for #gimme_da_issue! and other Issue methods
          desc 'Update an issue'
          argument :issue_ids, type: :array, required: true, desc: 'Issue IDs (i.e. CRY-1)'
          option :comment, type: :string, aliases: ['-m'], desc: 'Comment to add to the issue. - openan editor'
          option :project, type: :string, aliases: ['-p'], desc: 'Project to move the issue to. - select from a list'
          option :cancel, type: :boolean, default: false, desc: 'Cancel the issue'
          option :close, type: :boolean, default: false, desc: 'Close the issue'
          option :reason, type: :string, aliases: ['--butwhy'], desc: 'Reason for closing the issue. - open an editor'
          option :trash,
                 type: :boolean,
                 default: false,
                 desc: 'Also trash the issue (--close and --cancel support this option)'

          example [
            '--comment "This is a comment" CRY-1 CRY2    # Add a comment to multiple issues',
            '--comment -                   CRY-1 CRY2    # Add a comment to multiple issues, open an editor',
            '--project "Manhattan" CRY-3 CRY-4           # Move tickets to a different project',
            '--close CRY-2                               # Close an issue. Will be prompted for a reason',
            '--close --reason "Done" CRY-1 CRY-2         # Close multiple issues with a reason',
            '--cancel --trash --reason "Garbage" CRY-2   # Cancel an issue, and throw it in the trash'
          ]

          def call(issue_ids:, **options)
            raise SmellsBad, 'No issue IDs provided!' if issue_ids.empty?
            raise SmellsBad, 'You may only open a PR against a single issue' if options[:pr] && issue_ids.size > 1

            logger.debug('Updating issues', issue_ids:, options:)
            Rubyists::Linear::Issue.find_all(issue_ids).each do |issue|
              update_issue(issue, **options) # defined in lib/linear/commands/issue.rb
            end
          end
        end
      end
    end
  end
end
