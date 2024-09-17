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
      end
    end
  end
end
