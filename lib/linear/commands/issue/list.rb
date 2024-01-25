# frozen_string_literal: true

require "semantic_logger"

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue
    M :user
    # Namespace for CLI
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
          end

          def issues_for(options)
            return Rubyists::Linear::User.me.issues if options[:mine]

            Rubyists::Linear::Issue.all
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
