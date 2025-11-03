# frozen_string_literal: true

require 'semantic_logger'
require 'git'
require_relative '../issue'

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue, :user, :label
    # Namespace for CLI
    module CLI
      module Issue
        Develop = Class.new Dry::CLI::Command
        # The Develop class is a Dry::CLI::Command to start/update development status of an issue
        class Develop
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions
          include Rubyists::Linear::CLI::Issue # for #gimme_da_issue! and other Issue methods

          desc 'Start or update development status of an issue'
          argument :issue_id, required: true, desc: 'The Issue (i.e. ISS-1)'

          def call(issue_id:, **options)
            logger.debug('Developing issue', options:)
            issue = gimme_da_issue!(issue_id, me: Rubyists::Linear::User.me)
            branch_name = issue.branchName
            branch = branch_for(branch_name)
            branch.checkout
            prompt.ok "Checked out branch #{branch_name}"
            pull_or_push_new_branch!(branch_name)
            prompt.ok 'Ready to develop!'
          end
        end
      end
    end
  end
end
