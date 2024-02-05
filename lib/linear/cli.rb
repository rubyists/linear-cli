# frozen_string_literal: true

require 'dry/cli'
require 'dry/cli/completion/command'
require_relative '../linear'
require 'semantic_logger'
require 'tty-markdown'
require 'tty-prompt'

# The Rubyists module is the top-level namespace for all Rubyists projects
module Rubyists
  module Linear
    # The CLI module is a Dry::CLI::Registry that contains all the commands
    module CLI
      include SemanticLogger::Loggable
      extend Dry::CLI::Registry

      def self.prompt
        @prompt ||= TTY::Prompt.new
      end

      def self.register_sub!(command, sub_file, klass)
        # The filename is expected to define a class of the same name, but capitalized
        name = sub_file.basename('.rb').to_s
        subklass = klass.const_get(name.capitalize)
        if (aliases = klass::ALIASES[name.to_sym])
          command.register name, subklass, aliases: Array(aliases)
        else
          command.register name, subklass
        end
      end

      def self.register_subcommands!(command, name, klass)
        Pathname.new(__FILE__).dirname.join("commands/#{name}").glob('*.rb').each do |file|
          require file.expand_path
          register_sub! command, file, klass
        end
      end

      def self.load_and_register!(command)
        name = command.name.split('::').last.downcase
        command_aliases = command::ALIASES[name.to_sym] || []
        register name, aliases: Array(command_aliases) do |cmd|
          register_subcommands! cmd, name, command
        end
      end
    end
  end

  Pathname.new(__FILE__).dirname.join('cli').glob('*.rb').each do |file|
    require file.expand_path
  end

  # Load all our commands
  Pathname.new(__FILE__).dirname.join('commands').glob('*.rb').each do |file|
    require file.expand_path
  end

  module Linear
    # Open this back up to register 3rd party/other commands
    module CLI
      register 'completion', Dry::CLI::Completion::Command[self]
    end
  end
end
