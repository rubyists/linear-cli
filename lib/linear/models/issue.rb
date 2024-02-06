# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    M :base_model
    Issue = Class.new(BaseModel)
    M 'issue/class_methods'
    # The Issue class represents a Linear issue.
    class Issue
      include SemanticLogger::Loggable
      extend ClassMethods
      many_to_one :assignee, :User
      many_to_one :team, :Team

      BASIC_FILTER = { completedAt: { null: true } }.freeze

      Base = fragment('BaseIssue', 'Issue') do
        id
        identifier
        title
        branchName
        description
        createdAt
        updatedAt
      end

      def comment_fragment
        @comment_fragment ||= fragment('Comment', 'Comment') do
          id
          body
          url
        end
      end

      # Reference for this mutation:
      # https://studio.apollographql.com/public/Linear-API/variant/current/schema/reference/inputs/CommentCreateInput
      def add_comment(comment)
        id_for_this = identifier
        comment_frag = comment_fragment
        m = mutation { commentCreate(input: { issueId: id_for_this, body: comment }) { comment { ___ comment_frag } } }

        query_data = Api.query(m)
        query_data.dig(:commentCreate, :comment)
        self
      end

      def close_mutation(close_state, trash: false)
        id_for_this = identifier
        input = { stateId: close_state.id }
        input[:trash] = true if trash
        mutation { issueUpdate(id: id_for_this, input:) { issue { ___ Issue.full_fragment } } }
      end

      def close!(state: nil, trash: false)
        logger.warn "Using first completed state found: #{completed_states.first}" if state.nil?
        state ||= completed_states.first
        query_data = Api.query close_mutation(state, trash:)
        updated = query_data.dig(:issueUpdate, :issue)
        raise SmellsBad, "Unknown response for issue close: #{data} (should have :issueUpdate key)" if updated.nil?

        @data = @updated_data = updated
        self
      end

      def assign!(user)
        this_id = identifier
        m = mutation { issueUpdate(id: this_id, input: { assigneeId: user.id }) { issue { ___ Issue.full_fragment } } }
        query_data = Api.query(m)
        updated = query_data.dig(:issueUpdate, :issue)
        raise SmellsBad, "Unknown response for issue update: #{data} (should have :issueUpdate key)" if updated.nil?

        @data = @updated_data = updated
        self
      end

      def workflow_states
        @workflow_states ||= team.workflow_states
      end

      def inspection
        format('id: "%<identifier>s" title: "%<title>s"', identifier:, title:)
      end

      def to_s
        basic = format('%<id>-12s %<title>s', id: identifier, title:)
        return basic unless (name = data.dig(:assignee, :name))

        format('%<basic>s (%<name>s)', basic:, name:)
      end

      def parsed_description
        return TTY::Markdown.parse(description) if description && !description.empty?

        TTY::Markdown.parse(['# No Description For this issue??',
                             'Issues really need description',
                             "## What's up with that?"].join("\n"))
      rescue StandardError => e
        logger.error 'Error parsing description', e
        "Description was unparsable: #{description}\n"
      end

      def full
        sep = '-' * to_s.length
        format("%<to_s>s\n%<sep>s\n%<description>s\n", sep:, to_s:, description: parsed_description)
      end

      def display(options)
        printf "%s\n", (options[:full] ? full : to_s)
      end
    end
  end
end
