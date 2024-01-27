# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    L :api
    L :fragments
    M :base_model
    M :user
    Issue = Class.new(BaseModel)
    # The Issue class represents a Linear issue.
    class Issue
      include SemanticLogger::Loggable

      PLURAL = :issues
      BASIC_FILTER = { completedAt: { null: true } }.freeze

      Base = fragment('BaseIssue', 'Issue') do
        id
        identifier
        title
        assignee { ___ User::Base }
        createdAt
        updatedAt
      end

      def display
        format = "%-10s %s (%s)\n"
        printf format, data[:identifier], data[:title], data[:assignee][:name]
      end
    end
  end
end
