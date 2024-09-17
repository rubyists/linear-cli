# frozen_string_literal: true

require 'helper'

RSpec.describe 'Rubyists::Linear::Project' do
  let(:instance) { Rubyists::Linear::Project.new(attributes) }
  let(:attributes) do
    {
      id: SecureRandom.alphanumeric(32),
      name: "Project #{Time.now.to_i}",
      content: "Content at #{Time.now}",
      slugId: SecureRandom.alphanumeric(8),
      description: "Gadzooks! It's #{Time.now}!",
      url: 'https://linear.app/myorg/project/my-project-a2d0ddbbfbeb',
      createdAt: Time.now - 86_400,
      updatedAt: Time.now - 3600
    }
  end

  describe '#match_score?' do
    context 'when arg equals matching url' do
      subject { instance.match_score?(attributes.fetch(:url)) }

      it { is_expected.to eq(100) }
    end

    context 'when arg equals project ID' do
      subject { instance.match_score?(attributes.fetch(:id)) }

      it { is_expected.to eq(100) }
    end

    context 'when arg equals project name' do
      subject { instance.match_score?(attributes.fetch(:name)) }

      it { is_expected.to eq(100) }
    end

    context 'when arg is part of project name' do
      subject do
        # Argument is project name with 5 characters removed
        instance.match_score?(attributes.fetch(:name)[0..-5])
      end

      it { is_expected.to eq(75) }
    end

    context 'when description includes arg' do
      subject { instance.match_score?(project_name) }

      let(:project_name) { 'gadzooks' }

      it { is_expected.to eq(50) }
    end
  end
end
