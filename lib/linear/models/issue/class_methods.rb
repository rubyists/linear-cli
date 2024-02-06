# frozen_string_literal: true

module Rubyists
  # Namespace for Linear
  module Linear
    M :user, :team
    # The Issue class represents a Linear issue.
    class Issue
      # Class methods for Issue
      module ClassMethods
        def base_fragment
          @base_fragment ||= fragment('BaseIssue', 'Issue') do
            ___ Base
            assignee { ___ User.base_fragment }
            team { ___ Team.base_fragment }
          end
        end

        def full_fragment
          @full_fragment ||= fragment('FullIssue', 'Issue') do
            ___ Base
            assignee { ___ User.full_fragment }
            team { ___ Team.full_fragment }
          end
        end

        def find_all(*slugs)
          slugs.flatten.map { |slug| find(slug) }
        end

        def create(title:, description:, team:, project:, labels: [])
          team_id = team.id
          label_ids = labels.map(&:id)
          input = { title:, description:, teamId: team_id }
          input[:labelIds] = label_ids unless label_ids.empty?
          input[:projectId] = project.id if project
          m = mutation { issueCreate(input:) { issue { ___ Issue.base_fragment } } }
          query_data = Api.query(m)
          new query_data.dig(:issueCreate, :issue)
        end
      end
    end
  end
end
