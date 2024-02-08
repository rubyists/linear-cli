# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    M :base_model, :user
    Comment = Class.new(BaseModel)
    # The Comment class represents a Linear issue comment.
    class Comment
      include SemanticLogger::Loggable
      many_to_one :user

      Base = fragment('BaseComment', 'Comment') do
        id
        body
        url
        user { ___ User.base_fragment }
        createdAt
        updatedAt
      end

      def to_s
        format('%<id>-12s %<url>s', id:, url:)
      end

      def inspection
        format('id: "%<id>s" url: "%<url>s"', id:, url:)
      end
    end
  end
end
