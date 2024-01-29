# frozen_string_literal: true

require 'gqli'
require 'semantic_logger'
require 'sequel/extensions/inflector'

module Rubyists
  module Linear
    # Module which provides a base model for Linear models.
    class BaseModel
      extend GQLi::DSL
      include GQLi::DSL
      include SemanticLogger::Loggable

      # Methods for Linear models.
      module MethodMagic
        def self.included(base) # rubocop:disable Metrics/MethodLength
          base.instance_eval do
            base.base_fragment.__nodes.each do |node|
              sym = node.__name.to_sym
              define_method node.__name do
                updated_data[sym]
              end

              define_method "#{node.__name}=" do |value|
                updated_data[sym] = value
              end
            end
          end
        end
      end

      # Class methods for Linear models.
      class << self
        def const_added(const)
          return unless const == :Base

          include MethodMagic
        end

        def allq(filter: nil, limit: 50, after: nil)
          args = { first: limit }
          args[:filter] = filter ? basic_filter.merge(filter) : basic_filter
          args.delete(:filter) if args[:filter].empty?
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

        def just_name
          name.split('::').last
        end

        def base_fragment
          const_get(:Base)
        end

        def basic_filter
          return const_get(:BASIC_FILTER) if const_defined?(:BASIC_FILTER)

          {}
        end

        def plural
          return const_get(:PLURAL) if const_defined?(:PLURAL)

          just_name.downcase.pluralize.to_sym
        end

        def gql_query(filter: nil, after: nil)
          Api.query(allq(filter:, after:))
        end

        def all(after: nil, filter: nil, max: 100)
          edges = []
          moar = true
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

      attr_reader :data, :updated_data

      def initialize(data)
        data.each_key { |k| raise SmellsBad, "Unknown key #{k}" unless respond_to? "#{k}=" }
        @data = data
        @updated_data = data.dup
      end

      def changed?
        data != updated_data
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
