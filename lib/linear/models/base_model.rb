# frozen_string_literal: true

require 'gqli'
require 'semantic_logger'

module Rubyists
  module Linear
    # Module which provides a base model for Linear models.
    class BaseModel
      extend GQLi::DSL
      include GQLi::DSL
      include SemanticLogger::Loggable

      def self.included(klass)
        klass.extend ClassMethods
      end

      # Class methods for Linear models.
      module ClassMethods
        def allq(filter: nil, limit: 50, after: nil) # rubocop:disable Metrics/MethodLength
          args = { first: limit }
          args[:filter] = filter ? BASIC_FILTER.merge(filter) : BASIC_FILTER
          args[:after] = after if after
          query do
            subject(args) do
              edges do
                node { ___ Base }
                cursor
              end
              ___ Fragments::PageInfo
            end
          end
        end

        def gql_query(filter: nil, after: nil)
          Api.query(allq(filter:, after:))
        end

        def all(edges: [], moar: true, after: nil, filter: nil, max: 100)
          while moar
            data = gql_query(filter:, after:)
            subjects = data[PLURAL]
            edges += subjects[:edges]
            moar = false if edges.size >= max || !subjects[:pageInfo][:hasNextPage]
            after = subjects[:pageInfo][:endCursor]
          end
          edges.map { |edge| new edge[:node] }
        end
      end

      attr_reader :data

      def initialize(data)
        @data = data
      end

      def to_json(*_args)
        data.to_json
      end
    end
  end
end
