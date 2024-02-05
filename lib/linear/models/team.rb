# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    M :base_model, :issue, :user, :workflow_state
    Team = Class.new(BaseModel)
    # The Issue class represents a Linear issue.
    class Team
      include SemanticLogger::Loggable

      # TODO: Make this configurable
      BaseFilter = { # rubocop:disable Naming/ConstantName
        and: [
          { name: { notEndsWith: ' Releases' } },
          { name: { notEndsWith: '-ios' } },
          { name: { notEndsWith: '-android' } }
        ]
      }.freeze

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

      def label_query
        team_id = id
        query do
          team(id: team_id) do
            labels(first: 100, filter: BaseFilter) do
              nodes { ___ Label.base_fragment }
            end
          end
        end
      end

      def label_groups
        @label_groups ||= []
      end

      def labels # rubocop:disable Metrics/CyclomaticComplexity
        return @labels if @labels

        @labels = Api.query(label_query).dig(:team, :labels, :nodes)&.map do |label|
          label_groups << Label.new(label) if label[:isGroup]
          next if label[:isGroup] || label[:parent]

          Label.new label
        end&.compact
      end

      def members
        return @members if @members && !@members.empty?

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

      def workflow_states_query
        team_id = id
        query do
          team(id: team_id) do
            states do
              nodes { ___ WorkflowState.base_fragment }
            end
          end
        end
      end

      def workflow_states
        return @workflow_states if @workflow_states

        data = Api.query(workflow_states_query)
        @workflow_states = data.dig(:team, :states, :nodes)&.map do |state|
          WorkflowState.new state
        end
      end
    end
  end
end
