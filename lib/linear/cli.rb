# frozen_string_literal: true

require "dry/cli"
require "dry/cli/completion/command"
require_relative "../linear"

# The Rubyists module is the top-level namespace for all Rubyists projects
module Rubyists
  module Linear
    # The CLI module is a Dry::CLI::Registry that contains all the commands
    module CLI
      extend Dry::CLI::Registry

      # The CommonOptions module contains common options for all commands
      module CommonOptions
        def self.included(mod)
          mod.instance_eval do
            option :output, type: :string, default: "text", values: %w[text json], desc: "Output format"
            option :debug, type: :integer, default: 0, desc: "Debug level"
          end
        end
      end
    end
  end

  # Load all our commands
  Pathname.new(__FILE__).dirname.join("commands").glob("*.rb").each do |file|
    require file.expand_path
  end

  module Linear
    # Open this back up to register commands
    module CLI
      # Register all commands here
      register "issue", aliases: %w[i] do |issue|
        issue.register "ls", Issue::List
      end

      register "completion", Dry::CLI::Completion::Command[self]
    end
  end
end
