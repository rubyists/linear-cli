# frozen_string_literal: true

require "gqli"

module Rubyists
  # Namespace for Linear
  module Linear
    L :api
    # The Issue class represents a Linear issue.
    class Issue
      def self.allq(filter: nil) # rubocop:disable Metrics/MethodLength
        args = { first: 50 }
        args[:filter] = filter if filter
        GQLi::DSL.query do
          issues(args) do
            edges do
              node do
                id
                identifier
                title
                createdAt
                updatedAt
              end
              cursor
            end
            pageInfo do
              hasNextPage
              endCursor
            end
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
