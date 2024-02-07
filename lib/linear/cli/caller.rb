# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # This module is prepended to all commands to log their calls
      module Caller
        include SemanticLogger::Loggable
        def self.prepended(mod) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          # Global options for all commands
          mod.instance_eval do
            option :output, type: :string, default: 'text', values: %w[text json], desc: 'Output format'
            option :debug,
                   type: :integer,
                   aliases: ['-D'],
                   default: 0,
                   desc: 'Debug level (greater than 0 to see backtraces)'
          end

          Caller.class_eval do
            # Wraps the :call method so the debug option is honored, and we can trace the call
            # as well as handle any exceptions that are raised
            define_method :call do |**method_args| # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
              debug = method_args[:debug].to_i
              Rubyists::Linear.verbosity = debug
              logger.trace "Calling #{self.class} with #{method_args}"
              super(**method_args)
            rescue SmellsBad => e
              logger.error e.message
              exit 1
            rescue NotFoundError => e
              logger.error e.message
              exit 66
            rescue StandardError => e
              logger.error e.message
              logger.error e.backtrace.join("\n") if Rubyists::Linear.verbosity.positive?
              exit 5
            end
          end
        end
      end
    end
  end
end
