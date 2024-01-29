# frozen_string_literal: true

require 'dry/cli'
require 'dry/cli/completion/command'
require_relative '../linear'

# The Rubyists module is the top-level namespace for all Rubyists projects
module Rubyists
  module Linear
    # The CLI module is a Dry::CLI::Registry that contains all the commands
    module CLI
      extend Dry::CLI::Registry

      # The CommonOptions module contains common options for all commands
      module CommonOptions
        def self.included(mod)
          mod.instance_eval do
            option :output, type: :string, default: 'text', values: %w[text json], desc: 'Output format'
            option :debug, type: :integer, default: 0, desc: 'Debug level'
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

      # This module is prepended to all commands to log their calls
      module Caller
        LEVELS = %i[warn info debug trace].freeze
        def self.prepended(_mod) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          Caller.class_eval do
            define_method :call do |**method_args| # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
              debug = method_args[:debug].to_i
              Rubyists::Linear.verbosity = debug
              logger.trace "Calling #{self.class} with #{method_args}"
              super(**method_args)
            rescue SmellsBad => e
              logger.error e.message
              exit 1
            rescue StandardError => e
              logger.error e.message
              logger.error e.backtrace.join("\n")
              exit 5
            end
          end
        end
      end
    end
  end

  # Load all our commands
  Pathname.new(__FILE__).dirname.join('commands').glob('*.rb').each do |file|
    require file.expand_path
  end

  module Linear
    # Open this back up to register commands
    module CLI
      register 'completion', Dry::CLI::Completion::Command[self]
    end
  end
end
