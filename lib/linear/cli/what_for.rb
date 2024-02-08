# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # Module for the _for methods
      module WhatFor
        # TODO: Make this configurable
        ALLOWED_PR_TYPES = 'bug|fix|sec(urity)|feat(ure)|chore|refactor|test|docs|style|ci|perf'

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

        def ask_for_projects(projects, search: true)
          prompt.warn("No project found matching #{search}.") if search
          return projects.first if projects.size == 1

          prompt.select('Project:', projects.to_h { |p| [p.name, p] })
        end

        def project_scores(projects, search_term)
          projects.select { |p| p.match_score?(search_term).positive? }.sort_by { |p| p.match_score?(search_term) }
        end

        def project_for(team, project = nil) # rubocop:disable Metrics/AbcSize
          projects = team.projects
          return nil if projects.empty?

          possibles = project ? project_scores(projects, project) : []
          return ask_for_projects(projects, search: project) if possibles.empty?

          first = possibles.first
          return first if first.match_score?(project) == 100

          selections = possibles + (projects - possibles)
          prompt.select('Project:', selections.to_h { |p| [p.name, p] }) if possibles.size.positive?
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

          prompt.select('What type of PR is this?', %w[fix feature chore refactor test docs style ci perf security])
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
