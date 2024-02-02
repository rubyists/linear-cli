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
            logger.error('No teams found for you. Please join a team or pass an existing team name.')
            raise SmellsBad, 'No team given and none found for you'
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

          prompt.multiline('Description:').join(' ')
        end

        def title_for(title = nil)
          return title if title

          prompt.ask('Title:')
        end

        def labels_for(team, labels = nil)
          return Rubyists::Linear::Label.find_all_by_name(labels.map(&:strip)) if labels

          prompt.multi_select('Labels:', team.labels.to_h { |t| [t.name, t] })
        end
      end
    end
  end
end
