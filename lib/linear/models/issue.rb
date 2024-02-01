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

      class << self
        def find(slug)
          q = query { issue(id: slug) { ___ Base } }
          data = Api.query(q)
          raise NotFoundError, "Issue not found: #{slug}" if data.nil?

          new(data[:issue])
        end
      end

      def assign!(user)
        id_for_this = identifier
        m = mutation { issueUpdate(id: id_for_this, input: { assigneeId: user.id }) { issue { ___ Base } } }
        data = Api.query(m)
        updated = data.dig(:issueUpdate, :issue)
        raise SmellsBad, "Unknown response for issue update: #{data} (should have :issueUpdate key)" if updated.nil?

        Issue.new updated
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
        sep = '-' * to_s.length
        format("%<to_s>s\n%<sep>s\n%<description>s\n",
               sep:,
               to_s:,
               description: (TTY::Markdown.parse(data[:description]) rescue 'No Description?')) # rubocop:disable Style/RescueModifier
      end

      def display(options)
        printf "%s\n", (options[:full] ? full : to_s)
      end
    end
  end
end
