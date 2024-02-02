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

      Base = fragment('BaseTeam', 'Team') do
        description
        id
        key
        name
        createdAt
        updatedAt
      end

      def self.find(key)
        q = query do
          team(id: key) { ___ Base }
        end
        data = Api.query(q)
        hash = data[:team]
        raise NotFoundError, "Team not found: #{key}" unless hash

        new hash
      end

      def self.mine
        User.me.teams
      end

      def to_s
        format('%<name>s', name:)
      end

      def full
        format('%<key>-6s %<to_s>s', key:, to_s:)
      end

      def members
        return @members unless @members.empty?

        q = query do
          team(id:) do
            members do
              nodes { ___ User::Base }
            end
          end
        end
        data = Api.query(q)
        @members = data.dig(:team, :members, :nodes)&.map { |member| User.new member } || []
      end

      def display(_options)
        printf "%s\n", full
      end
    end
  end
end
