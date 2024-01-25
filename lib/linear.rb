# frozen_string_literal: true

require "pathname"
# Add the / operator for path separation
class Pathname
  def /(other)
    join(other.to_s)
  end
end

module Rubyists
  # Namespace for Linear classes
  module Linear
    # rubocop:disable Layout/SpaceAroundOperators
    ROOT = (Pathname(__FILE__)/"../..").expand_path
    LIBROOT = ROOT/:lib/:linear
    MODEL_ROOT = ROOT/:lib/:linear/:models
    SPEC_ROOT = ROOT/:spec
    FEATURE_ROOT = ROOT/:features

    def self.L(library) # rubocop:disable Naming/MethodName
      require LIBROOT/library
    end

    def self.M(model) # rubocop:disable Naming/MethodName
      require MODEL_ROOT/model
    end
    # rubocop:enable Layout/SpaceAroundOperators

    L :exceptions
    L :version
  end
end
