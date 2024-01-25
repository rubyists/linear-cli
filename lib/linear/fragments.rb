# frozen_string_literal: true

require "gqli"

module Rubyists
  module Linear
    # Reusable fragments
    module Fragments
      extend GQLi::DSL
      PageInfo = fragment("PageInfo", "PageInfo") do
        pageInfo do
          hasNextPage
          endCursor
        end
      end
    end
  end
end
