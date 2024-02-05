# frozen_string_literal: true

module Rubyists
  module Linear
    class BaseModel
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
    end
  end
end
