# frozen_string_literal: true

require 'semantic_logger'
require_relative '../issue'

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
          include Rubyists::Linear::CLI::Issue # for #gimme_da_issue! and other Issue methods
          desc 'Assign one or more issues to yourself'
          argument :issue_ids, type: :array, required: true, desc: 'Issue Identifiers'

          def call(issue_ids:, **options)
            updates = issue_ids.map do |issue_id|
              Rubyists::Linear::Issue.find(issue_id)
              gimme_da_issue! issue_id # gimme_da_issue! is defined in Rubyists::Linear::CLI::Issue
            rescue NotFoundError => e
              logger.warn e.message
              next
            end.compact
            display updates, options
          end
        end
      end
    end
  end
end
