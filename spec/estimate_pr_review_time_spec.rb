require 'spec_helper'
require 'json'
require_relative '../estimate_pr_review_time'

RSpec.describe PRReviewTimeEstimator do
  let(:github_token) { 'fake-token' }
  let(:repository) { 'org/repo' }
  let(:pr_number) { 42 }

  let(:mock_pr) do
    double('Sawyer::Resource',
      additions: 100,
      deletions: 20
    )
  end

  let(:mock_files) do
    [
      double('Sawyer::Resource', filename: 'app/models/user.rb'),
      double('Sawyer::Resource', filename: 'README.md'),
      double('Sawyer::Resource', filename: 'spec/models/user_spec.rb')
    ]
  end

  let(:mock_client) { instance_double(Octokit::Client) }

  subject(:estimator) { described_class.new(github_token, repository, pr_number) }

  before do
    allow(Octokit::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:user) # validate token
    allow(estimator).to receive(:config).and_return(
      {
        'time_thresholds' => { 'quick' => 300, 'standard' => 900 },
        'weights' => { 'lines_changed' => 0.8, 'files_modified' => 0.4, 'complexity' => 0.6 },
        'file_categories' => {
          'code' => ['.rb'],
          'documentation' => ['.md'],
          'tests' => ['_spec.rb']
        }
      }
    )
  end

  describe '#run' do
    before do
      allow(mock_client).to receive(:pull_request).with(repository, pr_number).and_return(mock_pr)
      allow(mock_client).to receive(:pull_request_files).with(repository, pr_number).and_return(mock_files)
      allow(mock_client).to receive(:add_labels_to_an_issue)
      allow(mock_client).to receive(:add_label)
    end

    it 'fetches PR data and applies label' do
      expect(mock_client).to receive(:pull_request).once
      expect(mock_client).to receive(:pull_request_files).once
      expect(mock_client).to receive(:add_labels_to_an_issue).with(repository, pr_number, array_including(/review-time:/))

      estimator.run
    end

    it 'creates the label if it does not exist' do
      expect(mock_client).to receive(:add_label).with(repository, kind_of(String), kind_of(String))
      estimator.run
    end

    it 'does not raise error if label already exists' do
      allow(mock_client).to receive(:add_label).and_raise(Octokit::UnprocessableEntity.new(status: 422))
      expect { estimator.run }.not_to raise_error
    end
  end

  describe '#determine_label' do
    it 'returns label under a minute' do
      expect(estimator.send(:determine_label, 45)).to eq('review-time: 45 seconds')
    end

    it 'returns label in minutes' do
      expect(estimator.send(:determine_label, 600)).to eq('review-time: 10 minutes')
    end

    it 'returns label over an hour' do
      expect(estimator.send(:determine_label, 3720)).to eq('review-time: 1h 2m')
    end
  end

  describe '#label_color' do
    it 'uses config to determine color: green' do
      expect(estimator.send(:label_color, 'review-time: 3 minutes')).to eq('2ecc71')
    end

    it 'uses config to determine color: yellow' do
      expect(estimator.send(:label_color, 'review-time: 10 minutes')).to eq('f1c40f')
    end

    it 'uses config to determine color: red' do
      expect(estimator.send(:label_color, 'review-time: 20 minutes')).to eq('e74c3c')
    end
  end
end
