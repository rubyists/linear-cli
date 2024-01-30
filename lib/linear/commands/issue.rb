# frozen_string_literal: true

module Rubyists
  module Linear
    # The Cli module is defined in cli.rb and is the top-level namespace for all CLI commands
    module CLI
      # This ALIASES hash will return the key as the value if the key is not found,
      # otherwise it will return the value of the existing key
      ALIASES = Hash.new { |h, k| h[k] = k }.merge(
        'list' => 'ls'
      )

      Pathname.new(__FILE__).dirname.join('issue').glob('*.rb').each do |file|
        require file.expand_path
        register 'issue', aliases: %w[i] do |issue|
          basename = File.basename(file, '.rb')
          # The filename is expected to define a class of the same name, but capitalized
          issue.register ALIASES[basename], Issue.const_get(basename.capitalize)
        end
      end
    end
  end
end
