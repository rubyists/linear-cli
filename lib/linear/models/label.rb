# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    L :api, :fragments
    M :base_model, :issue, :user, :team
    Label = Class.new(BaseModel)
    # The Label class represents a Linear issue label.
    class Label
      include SemanticLogger::Loggable

      PLURAL = :issueLabels
      Base = fragment('BaseLabel', 'IssueLabel') do
        id
        description
        name
        isGroup
        createdAt
        updatedAt
      end

      def self.base_fragment # rubocop:disable Metrics/AbcSize
        define_method(:team) { updated_data[:team] }
        define_method(:team=) { |val| updated_data[:team] = val }
        define_method(:parent) { updated_data[:parent] }
        define_method(:parent=) { |val| updated_data[:parent] = val }

        fragment('LabelWithTeams', 'IssueLabel') do
          ___ Base
          parent { ___ Base }
          team { ___ Team.base_fragment }
        end
      end

      def self.find_all_by_name(names)
        q = query do
          issueLabels(filter: { name: { in: names } }) do
            edges { node { ___ base_fragment } }
          end
        end
        data = Api.query(q)
        edges = data.dig(:issueLabels, :edges)
        raise NotFoundError, "No labels found: #{names}" unless edges

        edges.map { |edge| new edge[:node] }
      end

      def self.find_by_name(name)
        them = find_all_by_name([name])
        if them.size > 1
          logger.warn('Found multiple matches for label name, using the first one returned', labels: them)
        end
        them.first
      end

      def to_s
        format('%<name>s', name:)
      end

      def full
        format('%<to_s>-10s %<description>s', description:, to_s:)
      end

      def display(_options)
        printf "%s\n", full
      end
    end
  end
end
