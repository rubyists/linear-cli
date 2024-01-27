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

      include BaseModel::MethodMagic

      def inspect
        format '#<Rubyists::Linear::Issue:%<id>s id: %<identifier>s title: %<title>s>', id:, identifier:, title:
      end

      def to_s
        format('%<id>-12s %<title>s', id: data[:identifier], title: data[:title])
      end

      def full
        if (name = data.dig(:assignee, :name))
          format('%<basic>s (%<name>s)', basic: to_s, name:)
        else
          to_s
        end
      end

      def display
        printf "%s\n", full
      end
    end
  end
end
