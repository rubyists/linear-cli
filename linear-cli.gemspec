# frozen_string_literal: true

require_relative 'lib/linear'

Gem::Specification.new do |spec|
  spec.name = 'linear-cli'
  spec.version = Rubyists::Linear::VERSION
  spec.authors = ['Tj (bougyman) Vanderpoel']
  spec.email = ['tj@rubyists.com']

  spec.summary = 'CLI for interacting with Linear.app.'
  spec.description = 'A CLI for interacting with Linear.app. Loosely based on the GitHub CLI'
  spec.homepage = 'https://github.com/rubyists/linear-cli'
  spec.required_ruby_version = '>= 3.2.0'

  spec.license = 'MIT'
  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[pkg/ bin/ test/ spec/ features/ .git .github appveyor .rspec .rubocop cucumber.yml Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'base64', '~> 0.2'
  spec.add_dependency 'dry-cli', '~> 1.0'
  spec.add_dependency 'dry-cli-completion', '~> 1.0'
  spec.add_dependency 'gqli', '~> 1.2'
  spec.add_dependency 'httpx', '~> 1.2'
  spec.add_dependency 'semantic_logger', '~> 4.0'
  spec.add_dependency 'sequel', '~> 5.0'
  spec.add_dependency 'sqlite3', '~> 1.7'
  spec.add_dependency 'tty-markdown', '~> 0.7'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata['rubygems_mfa_required'] = 'true'
end
