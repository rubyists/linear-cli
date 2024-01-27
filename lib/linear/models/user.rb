# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    L :api
    M :base_model
    M :issue
    User = Class.new(BaseModel)
    # The User class represents a Linear user.
    class User
      include SemanticLogger::Loggable

      Base = fragment('BaseUser', 'User') do
        id
        name
        email
      end

      def self.me
        q = query do
          viewer do
            ___ Base
          end
        end
        data = Api.query(q)
        new data[:viewer]
      end

      def issue_query(first)
        id = data[:id]
        query do
          user(id:) do
            assignedIssues(first:, filter: { completedAt: { null: true } }) do
              nodes { ___ Issue::Base }
            end
          end
        end
      end

      def issues(limit: 50)
        data = Api.query(issue_query(limit))
        data[:user][:assignedIssues][:nodes].map do |issue|
          Issue.new issue
        end
      end

      def display
        format = "%-20s: %s <%s>\n"
        printf format, data[:id], data[:name], data[:email]
      end
    end
  end
end
