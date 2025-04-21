#!/usr/bin/env ruby
# frozen_string_literal: true

require 'octokit'
require 'logger'
require 'time'
require 'date'

# Simple statistics for arrays
class Array
  def mean
    return 0 if empty?

    sum.to_f / size
  end

  def percentile(percent)
    return nil if empty?
    return first if size == 1

    sorted = sort
    rank = (percent.to_f / 100) * (size - 1)
    calculate_percentile_value(sorted, rank)
  end

  private def calculate_percentile_value(sorted_array, rank)
    lower_index = rank.floor
    upper_index = rank.ceil
    lower_value = sorted_array[lower_index]

    return lower_value if lower_index == upper_index

    upper_value = sorted_array[upper_index]
    fraction = rank - lower_index
    lower_value + (fraction * (upper_value - lower_value))
  end
end

# Analyzes GitHub Pull Request review times and statistics
# Provides metrics about PR review times, merge times, and review counts
class PRReviewAnalytics
  attr_reader :repository, :client, :logger

  def initialize(options = {})
    @token = options[:token] || ENV['GITHUB_TOKEN']
    @repository = options[:repository] || ENV['REPOSITORY'] || ENV['GITHUB_REPOSITORY']
    @days_ago = options[:days_ago]&.to_i || 30
    @logger = Logger.new($stdout)
    @logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO

    validate_inputs
    setup_client
  end

  def validate_inputs
    return if @token && @repository

    @logger.error 'Missing GitHub token or repository!'
    @logger.error 'Set GITHUB_TOKEN and GITHUB_REPOSITORY environment variables or pass as options'
    exit 1
  end

  def setup_client
    @client = Octokit::Client.new(access_token: @token)
    @client.auto_paginate = true

    # Test the connection and validate repository
    begin
      @client.repository(@repository)
      @logger.info "Successfully connected to GitHub API and found repository: #{@repository}"
    rescue Octokit::Error => e
      @logger.error "Failed to connect to GitHub or repository not found: #{e.message}"
      exit 1
    end
  end

  def run
    since_date = Date.today - @days_ago
    @logger.info "Analyzing PRs closed since #{since_date}"

    prs = fetch_closed_prs(since_date)
    @logger.info "Found #{prs.size} PRs to analyze"

    if prs.empty?
      @logger.info 'No PRs found in the date range'
      return
    end

    analyze_prs(prs)
  end

  # Public for testing purposes
  def format_time(seconds)
    return 'N/A' unless seconds

    seconds = seconds.to_i
    days = seconds / 86_400
    hours = (seconds % 86_400) / 3_600
    minutes = (seconds % 3_600) / 60

    if days.positive?
      "#{days}d #{hours}h"
    elsif hours.positive?
      "#{hours}h #{minutes}m"
    elsif minutes.positive?
      "#{minutes}m"
    else
      "#{seconds}s"
    end
  end

  private

  def fetch_closed_prs(since_date)
    query = "repo:#{@repository} is:pr is:closed closed:>#{since_date.strftime('%Y-%m-%d')}"
    @logger.debug "Search query: #{query}"

    items = @client.search_issues(query).items

    # Fetch full PR data for each item
    items.map do |item|
      @client.pull_request(@repository, item.number)
    rescue StandardError => e
      @logger.warn "Error fetching PR ##{item.number}: #{e.message}"
      nil
    end.compact
  rescue StandardError => e
    @logger.error "Error fetching PRs: #{e.message}"
    []
  end

  def analyze_prs(prs)
    review_times = []
    merge_times = []
    review_counts = []

    prs.each do |pr|
      pr_number = pr.number
      @logger.debug "Analyzing PR ##{pr_number}: #{pr.title}"

      created_at = Time.parse(pr.created_at.to_s)
      closed_at = Time.parse(pr.closed_at.to_s)

      # Calculate merge time (time from PR creation to close)
      merge_time_seconds = (closed_at - created_at).to_i
      merge_times << merge_time_seconds

      # Fetch reviews for this PR
      begin
        reviews = @client.pull_request_reviews(@repository, pr_number)

        if reviews.empty?
          @logger.debug "PR ##{pr_number} has no reviews"
          next
        end

        review_counts << reviews.size

        first_review = reviews.min_by { |r| r.submitted_at if r.submitted_at }
        if first_review && first_review.submitted_at
          review_time = (Time.parse(first_review.submitted_at.to_s) - created_at).to_i
          review_times << review_time
        end
      rescue StandardError => e
        @logger.warn "Error fetching reviews for PR ##{pr_number}: #{e.message}"
      end
    end

    display_results(prs.size, review_times, merge_times, review_counts)
  end

  def display_results(pr_count, review_times, merge_times, review_counts)
    puts "\n----- GitHub PR Review Analytics for #{@repository} -----"
    puts "Analyzed #{pr_count} PRs closed in the last #{@days_ago} days"
    puts

    if review_times.empty?
      puts 'No review data found'
    else
      puts 'Time to First Review:'
      puts "  Average: #{format_time(review_times.mean)}"
      puts "  Median: #{format_time(review_times.percentile(50))}"
      puts "  90th percentile: #{format_time(review_times.percentile(90))}"
    end

    puts "\nTime to Merge:"
    puts "  Average: #{format_time(merge_times.mean)}"
    puts "  Median: #{format_time(merge_times.percentile(50))}"
    puts "  90th percentile: #{format_time(merge_times.percentile(90))}"

    return unless review_counts.any?

    puts format('  Average: %.1f', review_counts.mean)
    puts "\nReviews per PR:"
    puts "  Average: #{'%.1f' % review_counts.mean}"
    puts "  Maximum: #{review_counts.max}"
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {
    token: ENV['GITHUB_TOKEN'],
    repository: ENV['GITHUB_REPOSITORY'],
    days_ago: ENV['DAYS_AGO']
  }

  PRReviewAnalytics.new(options).run
end
