# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # Module for the _for methods
      module WhatFor
        include CLI::Projects # for methods called within #project_for

        # TODO: Make this configurable
        PR_TYPES = {
          fix: 'Bug fixes',
          feat: 'New feature work',
          chore: 'Chores and maintenance',
          eyes: 'Observability, metrics',
          test: 'Testing code',
          perf: 'Performance related work',
          refactor: 'Code refactoring',
          docs: 'Documentation Updates',
          sec: 'Security-related, including dependency updates',
          style: 'Style updates',
          ci: 'Continuous integration related',
          db: 'Database-Related (migrations, models, etc)'
        }.freeze

        PR_TYPE_SELECTIONS = PR_TYPES.invert

        ALLOWED_PR_TYPES = /#{PR_TYPES.keys.join("|")}/

        def editor_for(prefix)
          file = Tempfile.open(prefix, Rubyists::Linear.tmpdir)
          TTY::Editor.open(file.path)
          file.close
          File.readlines(file.path).map(&:chomp).join('\\n')
        ensure
          file&.close
        end

        def comment_for(issue, comment)
          ask_or_edit comment, "Comment for #{issue.identifier} - #{issue.title}"
        end

        def team_for(key = nil)
          return Rubyists::Linear::Team.find(key) if key

          ask_for_team
        end

        def reason_for(reason = nil, four: nil)
          question = four ? "Reason for #{TTY::Markdown.parse(four)}" : 'Reason'
          ask_or_edit reason, question
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

        def ask_or_edit(thing, question)
          return thing if thing && thing != '-'

          answer = prompt.ask("#{question}: ('-' to open an editor)", default: '-')
          return answer unless answer == '-'

          answer = editor_for [question.downcase, '.md']
          raise SmellsBad, "No content provided for #{question}" if answer.empty?

          answer
        end

        def description_for(description = nil)
          ask_or_edit description, 'Description'
        end

        def title_for(title = nil)
          return title if title

          prompt.ask('Title:')
        end

        def pr_title_for(issue)
          proposed = [pr_type_for(issue)]
          proposed_scope = pr_scope_for(issue.title)
          proposed << "(#{proposed_scope})" if proposed_scope
          summary = issue.title.sub(/(?:#{ALLOWED_PR_TYPES})(\([^)]+\))? /, '')
          proposed << ": #{issue.identifier} - #{summary}"
          prompt.ask("Title for PR for #{issue.identifier} - #{summary}", default: proposed.join)
        end

        def pr_description_for(issue)
          tmpfile = Tempfile.new([issue.identifier, '.md'], Rubyists::Linear.tmpdir)
          # TODO: Look up templates
          proposed = "# Context\n\n#{issue.description}\n\n## Issue\n\n#{issue.identifier}\n\n# Solution\n\n# Testing\n\n# Notes\n\n" # rubocop:disable Layout/LineLength
          tmpfile.write(proposed) && tmpfile.close
          desc = TTY::Editor.open(tmpfile.path)
          return tmpfile if desc

          File.open(tmpfile.path, 'w+') do |file|
            file.puts prompt.ask("Description for PR for #{issue.identifier} - #{issue.title}", default: proposed)
          end
          tmpfile
        end

        def pr_type_for(issue)
          proposed_type = issue.title.match(/^(#{ALLOWED_PR_TYPES})/i)
          return proposed_type[1].downcase if proposed_type

          prompt.select('What type of PR is this?', PR_TYPE_SELECTIONS)
        end

        def pr_scope_for(title)
          proposed_scope = title.match(/^\w+\(([^\)]+)\)/)
          return proposed_scope[1].downcase if proposed_scope

          scope = prompt.ask('What is the scope of this PR?', default: 'none')
          return nil if scope.empty? && scope == 'none'

          scope
        end

        def labels_for(team, labels = nil)
          return Rubyists::Linear::Label.find_all_by_name(labels.map(&:strip)) if labels

          prompt.multi_select('Labels:', team.labels.to_h { |t| [t.name, t] })
        end
      end
    end
  end
end
