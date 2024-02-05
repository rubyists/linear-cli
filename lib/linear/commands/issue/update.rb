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
          argument :issue_ids, type: :array, required: true, desc: 'Issue IDs (i.e. ISS-1)'
          option :comment, type: :string, aliases: ['--message'], desc: 'Comment to add to the issue'
          option :pr, type: :boolean, aliases: ['--pull-request'], default: false, desc: 'Create a pull request'
          option :close, type: :boolean, default: false, desc: 'Close the issue'
          option :reason, type: :string, aliases: ['--close-reason'], desc: 'Reason for closing the issue'

          def call(issue_ids:, **options)
            logger.debug('Updating issues', issue_ids:, options:)
            Rubyists::Linear::Issue.find_all(issue_ids).each do |issue|
              update_issue(issue, **options)
            end
          end
        end
      end
    end
  end
end
