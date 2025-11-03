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
        Pr = Class.new Dry::CLI::Command
        # The Develop class is a Dry::CLI::Command to start/update development status of an issue
        class Pr
          include SemanticLogger::Loggable
          include Rubyists::Linear::CLI::CommonOptions
          include Rubyists::Linear::CLI::Issue # for #gimme_da_issue! and other Issue methods

          desc 'Create a PR for an issue and push it to the remote'
          argument :issue_id, required: true, desc: 'The Issue (i.e. CRY-1)'
          option :title, required: false, desc: 'The title of the PR'
          option :description, required: false, desc: 'The description of the PR'

          def call(issue_id:, **options)
            logger.debug('Creating  PR for issue issue', options:)
            issue = gimme_da_issue!(issue_id, me: Rubyists::Linear::User.me)
            branch_name = issue.branchName
            branch = branch_for(branch_name)
            branch.checkout
            prompt.ok "Checked out branch #{branch_name}"
            issue_pr(issue, **options)
          end
        end
      end
    end
  end
end
