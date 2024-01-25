# frozen_string_literal: true

require "gqli"

module Rubyists
  # Namespace for Linear
  module Linear
    L :api
    # The Issue class represents a Linear issue.
    class Issue
      extend GQLi::DSL
      include GQLi::DSL
      include SemanticLogger::Loggable

      Base = fragment("BaseIssue", "Issue") do
        id
        identifier
        title
        createdAt
        updatedAt
      end

      PageInfo = fragment("PageInfo", "PageInfo") do
        pageInfo do
          hasNextPage
          endCursor
        end
      end

      def self.allq(filter: nil) # rubocop:disable Metrics/MethodLength
        args = { first: 50 }
        args[:filter] = filter if filter
        query do
          issues(args) do
            edges do
              node { ___ Base }
              cursor
            end
            ___ PageInfo
          end
        end
      end

      def self.all(filter: nil)
        data = Api.query(allq(filter:))
        data[:issues][:edges].map do |edge|
          new edge[:node]
        end
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
