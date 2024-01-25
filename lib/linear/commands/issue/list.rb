# frozen_string_literal: true

module Rubyists
  # Namespace for Linear
  module Linear
    M :issue
    module CLI
      module Issue
        List = Class.new Dry::CLI::Command
        # The List class is a Dry::CLI::Command that lists issues
        class List
          include Rubyists::Linear::CLI::CommonOptions

          option :mine, type: :boolean, desc: "Only show my issues"
          option :id, type: :string, desc: "Only show issues whose identifier starts with this"

          def call(**options)
            puts "Listing issues"
            issues = if options[:mine]
                       Rubyists::Linear::User.me.issues
                     else
                       Rubyists::Linear::Issue.all(filter: filter(options))
                     end
            display issues, options
          end

          def filter(options)
            return nil unless options.keys.any? { |k| %i[id].include? k }

            { identifier: { startsWith: options[:id] } } if options[:id]
          end

          def display(issues, options)
            return puts "No issues found" if issues.empty?
            return JSON.pretty_generate(issues) if options[:output] == "json"

            issues.each(&:display)
          end
        end
      end
    end
  end
end
