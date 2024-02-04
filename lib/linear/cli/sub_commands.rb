# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # The SubCommands module should be included in all commands with subcommands
      module SubCommands
        def self.included(mod)
          mod.instance_eval do
            def const_added(const)
              return unless const == :ALIASES

              Rubyists::Linear::CLI.load_and_register! self
            end
          end
        end

        def choose_a_team!(teams)
          prompt.on(:keypress) do |event|
            prompt.trigger(:keydown) if event.value == 'j'
            prompt.trigger(:keyup) if event.value == 'k'
          end
          key = prompt.select('Choose a team', teams.to_h { |t| [t.name, t.key] })
          Rubyists::Linear::Team.find key
        end

        def ask_for_team
          teams = Rubyists::Linear::Team.mine
          if teams.size == 1
            logger.info('Only one team found, using it', team: teams.first.name)
            teams.first
          elsif teams.empty?
            logger.error('No teams found for you. Please join a team or pass an existing team ID.')
            raise SmellsBad, 'No team given and none found for you (try joining a team or use a team id from `lc teams --no-mine`)' # rubocop:disable Layout/LineLength
          else
            choose_a_team! teams
          end
        end

        def prompt
          @prompt ||= CLI.prompt
        end

        def team_for(key = nil)
          return Rubyists::Linear::Team.find(key) if key

          ask_for_team
        end

        def description_for(description = nil)
          return description if description

          prompt.multiline('Description:').map(&:chomp).join('\\n')
        end

        def title_for(title = nil)
          return title if title

          prompt.ask('Title:')
        end

        def labels_for(team, labels = nil)
          return Rubyists::Linear::Label.find_all_by_name(labels.map(&:strip)) if labels

          prompt.on(:keypress) do |event|
            prompt.trigger(:keydown) if event.value == 'j'
            prompt.trigger(:keyup) if event.value == 'k'
          end
          prompt.multi_select('Labels:', team.labels.to_h { |t| [t.name, t] })
        end

        def cut_branch!(branch_name)
          if current_branch != default_branch
            prompt.yes?("You are not on the default branch (#{default_branch}). Do you want to checkout #{default_branch} and create a new branch?") && git.checkout(default_branch) # rubocop:disable Layout/LineLength
          end
          git.branch(branch_name)
        end

        def branch_for(branch_name)
          logger.trace('Looking for branch', branch_name:)
          existing = git.branches[branch_name]
          return cut_branch!(branch_name) unless existing

          logger.trace('Branch found', branch: existing&.name)
          existing
        end

        def current_branch
          git.current_branch
        end

        # Horrible way to do this, but it is working for now
        def pull_or_push_new_branch!(branch_name)
          git.pull
        rescue Git::FailedError
          prompt.warn("Upstream branch not found, pushing local #{branch_name} to origin")
          git.push('origin', branch_name)
          `git branch --set-upstream-to=origin/#{branch_name} #{branch_name}`
          prompt.ok("Set upstream to origin/#{branch_name}")
        end

        def git
          @git ||= Git.open('.')
        rescue Git::Repository::NoRepositoryError => e
          logger.error('Your current directory is not a git repository!', error: e)
          exit 121
        end

        def default_branch
          @default_branch ||= Git.default_branch git.remote.url
        end
      end
    end
  end
end
