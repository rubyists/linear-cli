# frozen_string_literal: true

require 'httpx'
require 'semantic_logger'

module Rubyists
  module Linear
    # Responsible for making requests to the Linear API
    class GraphApi
      include SemanticLogger::Loggable
      BASE_URI = 'https://api.linear.app/graphql'
      RETRY_AFTER = lambda do |*|
        @retries ||= 0
        @retries += 1
        seconds = @retries * 2
        logger.warn("Retry number #{@retries}, retrying after #{seconds} seconds")
        seconds
      end

      def session
        return @session if @session

        @session = HTTPX.plugin(:retries, retry_after: RETRY_AFTER, max_retries: 5).with(headers:)
      end

      def headers
        @headers ||= {
          'Content-Type' => 'application/json',
          'Authorization' => api_key
        }
      end

      def call(body)
        res = session.post(BASE_URI, body:)
        raise SmellsBad, "Bad Response from #{BASE_URI}: #{res}" if res.error

        data = JSON.parse(res.body.read, symbolize_names: true)
        raise SmellsBad, "No Data Returned for #{body}" unless data&.key?(:data)

        data[:data]
      end

      def query(query)
        call format('{ "query": "%s" }', query.to_s.gsub("\n", '').gsub('"', '\"'))
      end

      def api_key
        @api_key ||= ENV.fetch('LINEAR_API_KEY')
      end
    end
    Api = Rubyists::Linear::GraphApi.new
  end
end
