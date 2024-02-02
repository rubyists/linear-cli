# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # The CommonOptions module contains common options for all commands
      module CommonOptions
        def self.included(mod)
          mod.instance_eval do
            extend Rubyists::Linear::CLI::Watcher
          end
        end

        def display(subject, options)
          return puts(JSON.pretty_generate(subject)) if options[:output] == 'json'
          return subject.each { |s| s.display(options) } if subject.respond_to?(:each)
          unless subject.respond_to?(:display)
            raise SmellsBad, "Cannot display #{subject}, there is no #display method and it is not a collection"
          end

          subject.display(options)
        end
      end
    end
  end
end
