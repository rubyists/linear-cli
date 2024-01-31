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
          argument :issue_id, required: true, desc: 'Issue Identifier'

          def call(issue_id:, **options)
            me = Rubyists::Linear::User.me
            logger.debug 'Taking issue', issue_id:, assignee: me.to_h
            issue = Rubyists::Linear::Issue.find(issue_id)
            updated = issue.assign! Rubyists::Linear::User.me
            logger.debug 'Issue taken', issue: updated
            display updated, options
          end
        end
      end
    end
  end
end
