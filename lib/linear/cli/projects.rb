# frozen_string_literal: true

module Rubyists
  module Linear
    module CLI
      # The Project module contains support for finding and selecting projects
      # as part of a filter or query
      module Projects
        def ask_for_projects(projects, search: true)
          prompt.warn("No project found matching #{search}.") if search
          return projects.first if projects.size == 1

          prompt.select('Project:', projects.to_h { |p| [p.name, p] })
        end

        def project_scores(projects, search_term)
          projects.select { |p| p.match_score?(search_term).positive? }.sort_by { |p| p.match_score?(search_term) }
        end

        def project_for(project = nil, projects: Project.all)
          return nil if projects.empty?

          possibles = project ? project_scores(projects, project) : []
          return ask_for_projects(projects, search: project) if possibles.empty?

          first = possibles.first
          return first if first.match_score?(project) == 100

          selections = possibles + (projects - possibles)
          prompt.select('Project:', selections.to_h { |p| [p.name, p] }) if possibles.size.positive?
        end
      end
    end
  end
end
