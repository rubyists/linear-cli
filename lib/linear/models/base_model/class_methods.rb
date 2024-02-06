# frozen_string_literal: true

module Rubyists
  module Linear
    class BaseModel
      # Class methods for Linear models.
      module ClassMethods
        def setter!(relation, klass)
          define_method "#{relation}=" do |val|
            hash = val.is_a?(Hash) ? val : val.updated_data
            updated_data[relation] = hash
            instance_variable_set("@#{relation}", Rubyists::Linear.const_get(klass).new(hash))
          end
        end

        def getter!(relation)
          define_method relation do
            return instance_variable_get("@#{relation}") if instance_variable_defined?("@#{relation}")

            return unless (val = updated_data[relation])

            send("#{relation}=", val)
          end
        end

        def many_to_one(relation, klass = nil)
          klass ||= relation.to_s.camelize.to_sym
          getter! relation
          setter! relation, klass
        end

        alias one_to_one many_to_one

        def many_setter!(relation, klass)
          define_method "#{relation}=" do |val|
            vals = if val&.key?(:nodes)
                     val[:nodes]
                   else
                     Array(val)
                   end
            updated_data[relation] = vals.map { |v| v.is_a?(Hash) ? v : v.updated_data }
            new_relations = vals.map { |v| v.is_a?(Hash) ? Rubyists::Linear.const_get(klass).new(v) : v }
            instance_variable_set("@#{relation}", new_relations)
          end
        end

        def one_to_many(relation, klass = nil)
          klass ||= relation.to_s.singularize.camelize.to_sym
          getter! relation
          many_setter! relation, klass
        end

        def find(id_val)
          camel_name = just_name.camelize :lower
          ff = full_fragment
          query_data = Api.query(query { __node(camel_name, id: id_val) { ___ ff } })
          new query_data[camel_name.to_sym]
        end

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

        def full_fragment
          base_fragment
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
    end
  end
end
