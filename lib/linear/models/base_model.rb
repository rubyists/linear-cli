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

      # Class methods for Linear models.
      class << self
        def allq(filter: nil, limit: 50, after: nil)
          args = { first: limit }
          args[:filter] = filter ? basic_filter.merge(filter) : basic_filter
          args[:after] = after if after
          all_query args, plural.to_s, base_fragment
        end

        def all_query(args, subject, base_fragment)
          query do
            __node(subject, args) do
              edges do
                node { ___ base_fragment }
                cursor
              end
              ___ Fragments::PageInfo
            end
          end
        end

        def base_fragment
          const_get(:Base)
        end

        def basic_filter
          const_get(:BASIC_FILTER)
        end

        def plural
          const_get(:PLURAL)
        end

        def gql_query(filter: nil, after: nil)
          Api.query(allq(filter:, after:))
        end

        def all(edges: [], moar: true, after: nil, filter: nil, max: 100)
          while moar
            data = gql_query(filter:, after:)
            subjects = data[plural]
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
