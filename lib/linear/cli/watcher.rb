# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # Watch for the call method to be added to a command
      module Watcher
        def self.extended(_mod)
          define_method :method_added do |method_name|
            return unless method_name == :call

            prepend Rubyists::Linear::CLI::Caller
          end
        end
      end
    end
  end
end
