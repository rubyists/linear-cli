# frozen_string_literal: true

require "gqli"

module Rubyists
  # Namespace for Linear
  module Linear
    L :api
    L :fragments
    # The Issue class represents a Linear issue.
    class Issue
      extend GQLi::DSL
      include GQLi::DSL
      include SemanticLogger::Loggable

      BASIC_FILTER = { completedAt: { null: true } }.freeze

      Base = fragment("BaseIssue", "Issue") do
        id
        identifier
        title
        createdAt
        updatedAt
      end

      def self.allq(filter: nil, limit: 50, after: nil) # rubocop:disable Metrics/MethodLength
        args = { first: limit }
        args[:filter] = filter ? BASIC_FILTER.merge(filter) : BASIC_FILTER
        args[:after] = after if after
        query do
          issues(args) do
            edges do
              node { ___ Base }
              cursor
            end
            ___ Fragments::PageInfo
          end
        end
      end

      def self.issues_query(filter: nil, after: nil)
        Api.query(allq(filter:, after:))
      end

      def self.all(edges: [], moar: true, after: nil, filter: nil, max: 100)
        while moar
          data = issues_query(filter:, after:)
          issues = data[:issues]
          edges += issues[:edges]
          moar = false if edges.size >= max || !issues[:pageInfo][:hasNextPage]
          after = issues[:pageInfo][:endCursor]
        end
        edges.map { |edge| new edge[:node] }
      end

      attr_reader :issue

      def initialize(issue)
        @issue = issue
      end

      def to_json(*_args)
        issue.to_json
      end

      def display
        format = "%-10s %s\n"
        printf format, issue[:identifier], issue[:title]
      end
    end
  end
end
