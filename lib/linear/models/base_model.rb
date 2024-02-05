# frozen_string_literal: true

require 'gqli'
require 'semantic_logger'
require 'sequel/extensions/inflector'

module Rubyists
  #  Namespace for Linear
  module Linear
    L :api, :fragments
    M 'base_model/method_magic', 'base_model/class_methods'
    # The base model for all Linear models
    class BaseModel
      extend GQLi::DSL
      include GQLi::DSL
      include SemanticLogger::Loggable
      extend ClassMethods
      attr_reader :data, :updated_data

      CANCELLED_STATES = %w[cancelled canceled].freeze

      def initialize(data)
        data.each_key { |k| raise SmellsBad, "Unknown key #{k}" unless respond_to? "#{k}=" }
        @data = data
        @updated_data = data.dup
      end

      def changed?
        data != updated_data
      end

      def completed_states
        workflow_states.select { |ws| ws.type == 'completed' }
      end

      def cancelled_states
        workflow_states.select { |ws| CANCELLED_STATES.include? ws.type }
      end

      def to_h
        updated_data
      end

      def to_json(*_args)
        updated_data.to_json
      end

      def inspection
        format('name: "%<name>s"', name:)
      end

      def inspect
        format '#<%<name>s:%<id>s %<inspection>s>', name: self.class.name, id:, inspection:
      end
    end
  end
end
