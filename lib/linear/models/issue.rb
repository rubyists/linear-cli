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

      BASIC_FILTER = { completedAt: { null: true } }.freeze

      Base = fragment('BaseIssue', 'Issue') do
        id
        identifier
        title
        assignee { ___ User::Base }
        description
        createdAt
        updatedAt
      end

      def inspection
        format('id: "%<identifier>s" title: "%<title>s"', identifier:, title:)
      end

      def to_s
        basic = format('%<id>-12s %<title>s', id: data[:identifier], title: data[:title])
        return basic unless (name = data.dig(:assignee, :name))

        format('%<basic>s (%<name>s)', basic:, name:)
      end

      def full
        format("%<to_s>s\n\n%<description>s", to_s:, description:)
      end

      def display(options)
        printf "%s\n\n", (options[:full] ? full : to_s)
      end
    end
  end
end
