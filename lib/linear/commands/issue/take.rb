# frozen_string_literal: true

require 'semantic_logger'

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue, :user
    # Namespace for CLI
    module CLI
      module Issue
        Take = Class.new Dry::CLI::Command
        # The Take class is a Dry::CLI::Command that assigns an issue to yourself
        class Take
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions
          desc 'Assign one or more issues to yourself'
          argument :issue_ids, type: :array, required: true, desc: 'Issue Identifiers'

          def call(issue_ids:, **options) # rubocop:disable Metrics/MethodLength
            me = Rubyists::Linear::User.me
            updates = issue_ids.map do |issue_id|
              issue = Rubyists::Linear::Issue.find(issue_id)
              logger.debug 'Taking issue', issue:, assignee: me
              updated = issue.assign! me
              logger.debug 'Issue taken', issue: updated
              updated
            rescue NotFoundError => e
              logger.error e.message
              next
            end.compact
            display updates, options
          end
        end
      end
    end
  end
end
