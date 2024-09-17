# frozen_string_literal: true

require 'gqli'

module Rubyists
  # Namespace for Linear
  module Linear
    M :base_model
    Project = Class.new(BaseModel)
    # The Project class represents a Linear workflow state.
    class Project
      include SemanticLogger::Loggable

      Base = fragment('BaseProject', 'Project') do
        id
        name
        content
        slugId
        description
        url
        createdAt
        updatedAt
      end

      def slug
        File.basename(url).sub("-#{slugId}", '')
      end

      def match_score?(string)
        return 100 if string.casecmp?(id) # allow search by ID, gleaned from `-D 3`
        return 100 if string.casecmp?(url) # allow searching via project URLs

        downed = string.downcase
        return 100 if downed.split.join('-') == slug || downed == name.downcase
        return 75 if name.include?(string) || slug.include?(downed)
        return 50 if description.downcase.include?(downed)

        0
      end

      def to_s
        format('%<name>-12s %<url>s', name:, url:)
      end

      def inspection
        format('name: "%<name>s" type: "%<url>s"', name:, url:)
      end
    end
  end
end
