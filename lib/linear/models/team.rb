# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    L :api, :fragments
    M :base_model, :issue, :user
    Team = Class.new(BaseModel)
    # The Issue class represents a Linear issue.
    class Team
      include SemanticLogger::Loggable

      Base = fragment('BaseIssue', 'Team') do
        id
        name
        createdAt
        updatedAt
      end

      WithMembers = fragment('WithMembers', 'Team') do
        ___ Base
        members do
          node { ___ User::Base }
        end
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
