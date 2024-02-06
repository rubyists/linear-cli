# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # Module for the _for methods
      module WhatFor
        def editor_for(prefix)
          file = Tempfile.open(prefix, Rubyists::Linear.tmpdir)
          TTY::Editor.open(file.path)
          file.close
          File.readlines(file.path).map(&:chomp).join('\\n')
        ensure
          file&.close
        end

        def comment_for(issue, comment)
          return comment unless comment.nil? || comment == '-'

          comment = prompt.ask("Comment for #{issue.identifier} - #{issue.title} (- to open an editor)", default: '-')
          return comment unless comment == '-'

          editor_for %w[comment .md]
        end

        def team_for(key = nil)
          return Rubyists::Linear::Team.find(key) if key

          ask_for_team
        end

        def reason_for(reason = nil, four: nil)
          return reason if reason

          question = four ? "Reason for #{four}:" : 'Reason:'
          prompt.ask(question)
        end

        def cancelled_state_for(thingy)
          states = thingy.cancelled_states
          return states.first if states.size == 1

          selection = prompt.select('Choose a cancelled state', states.to_h { |s| [s.name, s.id] })
          Rubyists::Linear::WorkflowState.find selection
        end

        def completed_state_for(thingy)
          states = thingy.completed_states
          return states.first if states.size == 1

          selection = prompt.select('Choose a completed state', states.to_h { |s| [s.name, s.id] })
          Rubyists::Linear::WorkflowState.find selection
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
      end
    end
  end
end
