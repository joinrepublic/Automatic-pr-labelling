require 'rspec'
require 'ostruct'
require_relative '../analyze_pr_review_times'

RSpec.describe PRReviewAnalytics do
  let(:logger) do
    instance_double(Logger, info: nil, error: nil, debug: nil, warn: nil).tap do |log|
      allow(log).to receive(:level=)
    end
  end
  let(:client) { instance_double(Octokit::Client) }
  let(:options) { { token: 'fake-token', repository: 'owner/repo', days_ago: 30 } }

  before do
    allow(Logger).to receive(:new).and_return(logger)
    allow(Octokit::Client).to receive(:new).and_return(client)
    allow(client).to receive(:auto_paginate=)
    allow(client).to receive(:repository).with('owner/repo')
  end

  subject(:analytics) { described_class.new(options) }

  describe '#format_time' do
    it 'formats seconds into days and hours' do
      expect(analytics.format_time(90000)).to eq("1d 1h")
    end

    it 'formats seconds into hours and minutes' do
      expect(analytics.format_time(3900)).to eq("1h 5m")
    end

    it 'formats seconds into minutes' do
      expect(analytics.format_time(120)).to eq("2m")
    end

    it 'formats seconds into seconds' do
      expect(analytics.format_time(45)).to eq("45s")
    end

    it 'returns N/A for nil' do
      expect(analytics.format_time(nil)).to eq("N/A")
    end
  end

  describe '#run' do
    let(:pr_items) { [OpenStruct.new(number: 1)]}
    before do
      allow(client).to receive(:search_issues).and_return(OpenStruct.new(items: pr_items))
    end

    context 'when no PRs are found' do
      let(:pr_items) { [] }

      it 'prints a message about no PRs found' do
        expect(analytics.logger).to receive(:info).with(/No PRs found/)
        analytics.run
      end
    end

    context 'when PRs are found but have no reviews' do
      let(:pr) { OpenStruct.new(number: 1, created_at: Time.now - 5000, closed_at: Time.now, title: "Test PR") }
      let(:pr_items) { [OpenStruct.new(number: pr.number)] }

      before do
        allow(client).to receive(:pull_request).and_return(pr)
        allow(client).to receive(:pull_request_reviews).with('owner/repo', pr.number).and_return([])
      end

      it 'analyzes PRs and prints merge time but not review stats' do
        expect(analytics.logger).to receive(:debug).with(/PR #1/)
        expect(client).to receive(:pull_request_reviews)
        expect { analytics.run }.to output(/Time to Merge:/).to_stdout
      end
    end

    context 'when a PR has reviews with timestamps' do
      let(:pr) do
        OpenStruct.new(
          number: 42,
          title: "Feature X",
          created_at: Time.now - 600,
          closed_at: Time.now
        )
      end
      let(:review) do
        OpenStruct.new(
          submitted_at: (Time.now - 300)
        )
      end
      let(:pr_items) { [OpenStruct.new(number: pr.number)] }

      before do
        allow(client).to receive(:pull_request).and_return(pr)
        allow(client).to receive(:pull_request_reviews).with('owner/repo', pr.number).and_return([review])
      end

      it 'prints time to first review and merge time' do
        expect { analytics.run }.to output(/Time to First Review:.*Time to Merge:/m).to_stdout
      end
    end

    context 'when a review has no submitted_at' do
      let(:pr) { OpenStruct.new(number: 5, title: "Bugfix", created_at: Time.now - 1000, closed_at: Time.now) }
      let(:review) { OpenStruct.new(submitted_at: nil) }
      let(:pr_items) { [OpenStruct.new(number: pr.number)] }

      before do
        allow(client).to receive(:pull_request).and_return(pr)
        allow(client).to receive(:pull_request_reviews).with('owner/repo', pr.number).and_return([review])
      end

      it 'handles nil review timestamps gracefully' do
        expect { analytics.run }.to output(/Time to Merge:/).to_stdout
      end
    end

    context 'when fetching reviews fails for a PR' do
      let(:pr) { OpenStruct.new(number: 2, created_at: Time.now - 3000, closed_at: Time.now, title: "Edge Case PR") }
      let(:pr_items) { [OpenStruct.new(number: pr.number)] }

      before do
        allow(client).to receive(:pull_request).and_return(pr)
	allow(client).to receive(:pull_request_reviews).and_raise(StandardError.new("API failure"))
      end

      it 'warns and skips the PR' do
        expect(logger).to receive(:warn).with(/Error fetching reviews/)
        analytics.run
      end
    end

    context 'when fetching PRs fails entirely' do
      before do
        allow(client).to receive(:search_issues).and_raise(StandardError.new("Rate limit"))
      end

      it 'logs error and continues gracefully' do
        expect(logger).to receive(:error).with(/Error fetching PRs/)
        expect { analytics.run }.not_to raise_error
      end
    end
  end
end
