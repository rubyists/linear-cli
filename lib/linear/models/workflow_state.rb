# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    M :base_model
    WorkflowState = Class.new(BaseModel)
    # The WorkflowState class represents a Linear workflow state.
    class WorkflowState
      include SemanticLogger::Loggable

      Base = fragment('BaseWorkflowState', 'WorkflowState') do
        id
        name
        position
        type
        description
        createdAt
        updatedAt
      end

      def to_s
        format('%<name>-12s %<type>s', name:, type:)
      end

      def inspection
        format('name: "%<name>s" type: "%<type>s"', name:, type:)
      end
    end
  end
end
