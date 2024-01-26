# frozen_string_literal: true

require_relative '../helper'

RSpec.describe 'Rubyists::Linear::CLI' do
  it 'has a version number' do
    expect(Rubyists::Linear::VERSION).not_to be_nil
  end
end
