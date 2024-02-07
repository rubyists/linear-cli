# frozen_string_literal: true

require 'semantic_logger'
require_relative '../issue'

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue, :user, :label
    # Namespace for CLI
    module CLI
      module Issue
        Create = Class.new Dry::CLI::Command
        # The Create class is a Dry::CLI::Command to create a new issue
        class Create
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions
          include Rubyists::Linear::CLI::Issue # for #gimme_da_issue! and other Issue methods
          desc 'Create a new issue'
          option :title, type: :string, aliases: ['-t'], desc: 'Issue Title'
          option :description, type: :string, aliases: ['-d'], desc: 'Issue Description'
          option :team, type: :string, aliases: ['-T'], desc: 'Team Identifier'
          option :labels, type: :array, aliases: ['-l'], desc: 'Labels for the issue (Comma separated list)'
          option :project, type: :string, aliases: ['-p'], desc: 'Project Identifier'
          option :develop, type: :boolean, aliases: ['--dev'], desc: 'Start development after creating the issue'

          def call(**options)
            logger.debug('Creating issue', options:)
            issue = make_da_issue!(**options)
            logger.debug('Issue created', issue:)
            prompt.yes?('Do you want to take this issue?') && gimme_da_issue!(issue.id, me: User.me)
            display issue, options
            Rubyists::Linear::CLI::Issue::Develop.new.call(issue_id: issue.id, **options) if options[:develop]
          end
        end
      end
    end
  end
end
