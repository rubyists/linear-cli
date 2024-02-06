# frozen_string_literal: true

module Rubyists
  module Linear
    class BaseModel
      # Methods for Linear models.
      module MethodMagic
        def self.included(base) # rubocop:disable Metrics/AbcSize
          base.instance_eval do
            base.base_fragment.__nodes.each do |node|
              sym = node.__name.to_sym
              define_method(sym) { updated_data[sym] } unless instance_methods.include? sym
              esym = :"#{sym}="
              next if instance_methods.include? esym

              define_method(esym) { |value| updated_data[sym] = value }
            end
          end
        end
      end
    end
  end
end
