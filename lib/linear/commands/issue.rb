# frozen_string_literal: true

require_relative '../cli/sub_commands'

module Rubyists
  module Linear
    # The Cli module is defined in cli.rb and is the top-level namespace for all CLI commands
    module CLI
      # The Issue module is the namespace for all issue-related commands, and
      # should be included in any command that deals with issues
      module Issue
        include CLI::SubCommands
        # Aliases for Issue commands
        ALIASES = {
          create: %w[c new add],        # aliases for the create command
          list: %w[l ls],               # aliases for the list command
          show: %w[s view v display d], # aliases for the show command
          issue: %w[i issues]           # aliases for the main issue command itself
        }.freeze

        def make_da_issue!(**options)
          # These *_for methods are defined in Rubyists::Linear::CLI::SubCommands
          title = title_for options[:title]
          description = description_for options[:description]
          team = team_for options[:team]
          require 'pry'; binding.pry
          labels = labels_for team, options[:labels]
          Rubyists::Linear::Issue.create(title:, description:, team:, labels:)
        end

        def gimme_da_issue!(issue_id, me) # rubocop:disable Naming/MethodParameterName
          issue = Rubyists::Linear::Issue.find(issue_id)
          logger.debug 'Taking issue', issue:, assignee: me
          updated = issue.assign! me
          logger.debug 'Issue taken', issue: updated
          updated
        end
      end
    end
  end
end
