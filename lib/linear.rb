# frozen_string_literal: true

require 'pathname'
require 'semantic_logger'
SemanticLogger.default_level = :info
SemanticLogger.add_appender(io: $stderr, formatter: :color)

# Add the / operator for path separation
class Pathname
  def /(other)
    join(other.to_s)
  end
end

module Rubyists
  # Namespace for Linear classes
  module Linear
    include SemanticLogger::Loggable
    # rubocop:disable Layout/SpaceAroundOperators
    ROOT = (Pathname(__FILE__)/'../..').expand_path
    LIBROOT = ROOT/:lib/:linear
    MODEL_ROOT = ROOT/:lib/:linear/:models
    SPEC_ROOT = ROOT/:spec
    FEATURE_ROOT = ROOT/:features
    DEBUG_LEVELS = %i[warn info debug trace].freeze

    def self.L(*libraries) # rubocop:disable Naming/MethodName
      Array(libraries).each { |library| require LIBROOT/library }
    end
    L :exceptions, :version

    def self.M(*models) # rubocop:disable Naming/MethodName
      Array(models).each { |model| require MODEL_ROOT/model }
    end
    # rubocop:enable Layout/SpaceAroundOperators

    def self.verbosity
      @verbosity ||= 0
    end

    def self.verbosity=(debug)
      return verbosity unless debug

      logger.warn 'Debug level should be between 0 and 3' unless debug.between?(0, 3)
      @verbosity = debug
      level = @verbosity > (DEBUG_LEVELS.size - 1) ? :trace : DEBUG_LEVELS[@verbosity]
      SemanticLogger.default_level = level
    end
  end
end
