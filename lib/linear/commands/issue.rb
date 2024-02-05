# frozen_string_literal: true

# This is where the #reason_for, #title_for, #description_for, #team_for, and #labels_for methods are defined
# as well as other helpers which are used in multiple commands and subcommands
# This is also where the #prompt method is defined, which is used to display messages to the user and get input
require_relative '../cli/sub_commands'

module Rubyists
  module Linear
    # The Cli module is defined in cli.rb and is the top-level namespace for all CLI commands
    module CLI
      # The Issue module is the namespace for all issue-related commands, and
      # should be included in any command that deals with issues
      module Issue
        include CLI::SubCommands

        DESCRIPTION = 'Manage issues'

        # Aliases for Issue commands
        ALIASES = {
          create: %w[c new add], # aliases for the create command
          develop: %w[d dev],    # aliases for the develop command
          list: %w[l ls],        # aliases for the list command
          update: %w[u],         # aliases for the close command
          issue: %w[i issues]    # aliases for the main issue command itself
        }.freeze

        def issue_comment(issue, comment)
          issue.add_comment(comment)
          prompt.ok("Comment added to #{issue.identifier}")
        end

        def cancel_issue(issue, **options)
          reason = reason_for(options[:reason], four: "cancelling #{issue.identifier} - #{issue.title}")
          issue_comment(issue, reason)
          cancel_state = cancel_state_for(issue)
          issue.close!(state: cancel_state, trash: options[:trash])
          prompt.ok("#{issue.identifier} was cancelled")
        end

        def close_issue(issue, **options)
          cancelled = options[:cancel]
          doing = cancelled ? 'cancelling' : 'closing'
          done = cancelled ? 'cancelled' : 'closed'
          workflow_state = cancelled ? cancelled_state_for(issue) : completed_state_for(issue)
          reason = reason_for(options[:reason], four: "#{doing} #{issue.identifier} - #{issue.title}")
          issue_comment(issue, reason)
          issue.close!(state: workflow_state, trash: options[:trash])
          prompt.ok("#{issue.identifier} was #{done}")
        end

        def issue_pr(issue)
          issue.create_pr!
          prompt.ok("Pull request created for #{issue.identifier}")
        end

        def update_issue(issue, **options)
          issue_comment(issue, options[:comment]) if options[:comment]
          return close_issue(issue, **options) if options[:close]
          return issue_pr(issue) if options[:pr]
          return if options[:comment]

          prompt.warn('No action taken, no options specified')
          prompt.ok('Issue was not updated')
        end

        def make_da_issue!(**options)
          # These *_for methods are defined in Rubyists::Linear::CLI::SubCommands
          title = title_for options[:title]
          description = description_for options[:description]
          team = team_for options[:team]
          labels = labels_for team, options[:labels]
          Rubyists::Linear::Issue.create(title:, description:, team:, labels:)
        end

        def gimme_da_issue!(issue_id, me: Rubyists::Linear::User.me) # rubocop:disable Naming/MethodParameterName
          logger.trace('Looking up issue', issue_id:, me:)
          issue = Rubyists::Linear::Issue.find(issue_id)
          if issue.assignee && issue.assignee[:id] == me.id
            prompt.say("You are already assigned #{issue_id}")
            return issue
          end

          prompt.say("Assigning issue #{issue_id} to ya")
          updated = issue.assign! me
          logger.trace 'Issue taken', issue: updated
          updated
        end
      end
    end
  end
end
