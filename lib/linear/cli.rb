# frozen_string_literal: true

require 'dry/cli'
require 'dry/cli/completion/command'
require_relative '../linear'
require 'semantic_logger'
require 'tty-markdown'
require 'tty-prompt'

module Dry
  class CLI
    module Completion
      # Monkeypatching the Generator just to add our 'lc' alias :(
      class Generator
        def call(shell:, include_aliases: false, out: StringIO.new) # rubocop:disable Metrics/MethodLength
          raise ArgumentError, 'Unknown shell' unless SUPPORTED_SHELLS.include?(shell)

          if shell == ZSH
            out.puts '# enable bash completion support, see https://github.com/dannyben/completely#completions-in-zsh'
            out.puts 'autoload -Uz +X compinit && compinit'
            out.puts 'autoload -Uz +X bashcompinit && bashcompinit'
          end

          out.puts Completely::Completions.new(
            Input.new(@registry, @program_name).call(include_aliases:)
          ).script
          # Here is the only change in our monkeypatch! Lame, right?
          out.puts 'complete -F _linear-cli_completions lc'
          out.string
        end
      end
    end
  end
end

# The Rubyists module is the top-level namespace for all Rubyists projects
module Rubyists
  module Linear
    # The CLI module is a Dry::CLI::Registry that contains all the commands
    module CLI
      include SemanticLogger::Loggable
      extend Dry::CLI::Registry

      def self.prompt
        return @prompt if @prompt

        @prompt = TTY::Prompt.new
        # This gives ex/vim style navigation to menus
        @prompt.on(:keypress) do |event|
          @prompt.trigger(:keydown) if event.value == 'j'
          @prompt.trigger(:keyup) if event.value == 'k'
        end
        @prompt
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

  # Load CLI Helpers/libraries
  Pathname.new(__dir__).join('cli').glob('*.rb').each do |file|
    require file.expand_path
  end

  # Load all our commands and subcommands
  Pathname.new(__dir__).join('commands').glob('*.rb').each do |file|
    require file.expand_path
  end

  module Linear
    # Open this back up to register 3rd party/other commands
    module CLI
      # NOTE: We have monkeypatched the Generator to add our 'lc' alias
      register 'completion', Dry::CLI::Completion::Command[self]
    end
  end
end
