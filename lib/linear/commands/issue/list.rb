# frozen_string_literal: true

require "semantic_logger"

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue
    M :user
    module CLI
      module Issue
        List = Class.new Dry::CLI::Command
        # The List class is a Dry::CLI::Command that lists issues
        class List
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions

          option :mine, type: :boolean, desc: "Only show my issues"

          def call(**options)
            logger.debug "Listing issues"
            display issues_for(options), options
          rescue SmellsBad => e
            logger.error e.message
            exit 1
          rescue StandardError => e
            logger.error e.message
            logger.error e.backtrace.join("\n") if Rubyists::Linear.verbosity > 0
            exit 5
          end

          def issues_for(options)
            return Rubyists::Linear::User.me.issues if options[:mine]

            Rubyists::Linear::Issue.all
          end

          def display(issues, options)
            return puts "No issues found" if issues.empty?
            return JSON.pretty_generate(issues) if options[:output] == "json"

            issues.each(&:display)
          end

          prepend Rubyists::Linear::CLI::Caller
        end
      end
      register "issue", aliases: %w[i] do |issue|
        issue.register "ls", Issue::List
      end
    end
  end
end
