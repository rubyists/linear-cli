# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    L :api
    M :base_model, :issue, :team
    User = Class.new(BaseModel)
    # The User class represents a Linear user.
    class User
      include SemanticLogger::Loggable

      Base = fragment('BaseUser', 'User') do
        id
        name
        email
      end

      WithTeams = fragment('UserWithTeams', 'User') do
        ___ Base
        teams do
          nodes { ___ Team::Base }
        end
      end

      def self.me(teams: false)
        fragment = teams ? WithTeams : Base
        q = query do
          viewer do
            ___ fragment
          end
        end
        data = Api.query(q)
        new data[:viewer]
      end

      def initialize(data)
        super(data)
        self.teams = data[:teams] if data.key? :teams
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
        issue_data = Api.query(issue_query(limit))
        issue_data[:user][:assignedIssues][:nodes].map do |issue|
          Issue.new issue
        end
      end

      def team_query(first)
        id = data[:id]
        query do
          user(id:) do
            teams(first:) do
              nodes { ___ Team::Base }
            end
          end
        end
      end

      def teams=(team_data)
        team_data.is_a?(Array) && @teams = team_data && return

        if team_data.is_a?(Hash)
          @teams = team_data[:nodes].map { |team| Team.new team }
          return
        end

        raise ArgumentError, "Don't know how to handle #{team_data.class}"
      end

      def teams(limit: 50)
        return @teams if @teams

        team_data = Api.query(team_query(limit))
        @teams = team_data[:user][:teams][:nodes].map do |team|
          Team.new team
        end
      end

      def to_s
        format('%<id>-20s: %<name>s <%<email>s>', id:, name:, email:)
      end

      def display(_options)
        return printf("%s\n", to_s) if @teams.nil?

        printf "%<to_s>s (%<teams>s)\n", to_s:, teams: @teams.map(&:name).join(', ')
      end
    end
  end
end
