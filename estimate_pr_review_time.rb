#! /usr/bin/env ruby
require 'octokit'
require 'json'
require 'yaml'
require 'logger'
require 'dotenv/load'

# Set up logging
# logger.rb (or just inline this method)
def default_logger
  logger = Logger.new(STDOUT)
  logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
  logger
end

# Configuration
class Config
  # Load from .pr-review-config.yml if exists, otherwise use defaults
  def self.load(logger, path)
    if File.exist?(path) && !File.directory?(path) && File.size(path) < 1_000_000
      config = YAML.safe_load_file(path, permitted_classes: [Hash, String, Array, Integer, Float, Symbol])
      config.is_a?(Hash) ? config : default_config
    else
      default_config
    end
  rescue Psych::SyntaxError, Errno::ENOENT, Errno::EACCES => e
    logger.warn("Failed to load config at #{path}: #{e.message}")
    default_config
  end

  def self.default_time_thresholds
    {
      'quick' => 300,    # 5 minutes in seconds
      'standard' => 900  # 15 minutes in seconds
    }
  end

  def self.default_weights
    {
      'lines_changed' => 0.8,
      'files_modified' => 0.4,
      'complexity' => 0.6
    }
  end

  def self.default_file_categories
    {
      'code' => ['.rb', '.js', '.py', '.java', '.php', '.go', '.ts', '.jsx', '.tsx'],
      'documentation' => ['.md', '.txt', '.rst', '.adoc'],
      'tests' => ['_spec.rb', '_test.rb', '.test.js', 'spec.js', 'test_', '_test.py']
    }
  end

  def self.default_config
    {
      'time_thresholds' => default_time_thresholds,
      'weights' => default_weights,
      'file_categories' => default_file_categories
    }
  end
end

# Main class for estimating PR review time
module PRComplexityCalculator
  def calculate_complexity_factor(file_list)
    counts = count_file_categories(file_list)
    complexity = calculate_weighted_complexity(counts)
    normalize_complexity(complexity)
  end

  private

  def count_file_categories(file_list)
    counts = { code: 0, tests: 0, docs: 0 }
    categorize_files(file_list, counts)
    counts
  end

  def categorize_files(file_list, counts)
    file_list.each do |file|
      name = file.filename.downcase
      update_category_counts(name, counts)
    end
  end

  def update_category_counts(filename, counts)
    cats = config['file_categories']
    counts[:code] += 1 if cats['code'].any? { |ext| filename.end_with?(ext) }
    counts[:tests] += 1 if cats['tests'].any? { |pat| filename.include?(pat) }
    counts[:docs] += 1 if cats['documentation'].any? { |ext| filename.end_with?(ext) }
  end

  def calculate_weighted_complexity(counts)
    counts[:code] * 1.5 + counts[:tests] * 1.0 + counts[:docs] * 0.5
  end

  def normalize_complexity(value)
    [[value / 5, 1].max, 10].min
  end
end

module PRTimeCalculator
  def calculate_review_time(pull_request, file_list)
    lines_changed = pull_request.additions + pull_request.deletions
    weights = config['weights']

    total_time = calculate_total_review_time(lines_changed, file_list, weights)
    [total_time, 60].max # Minimum 1 minute
  end

  private

  def calculate_total_review_time(lines, files, weights)
    [
      calculate_lines_time(lines, weights['lines_changed']),
      calculate_files_time(files.length, weights['files_modified']),
      calculate_complexity_time(files, weights['complexity'])
    ].sum
  end

  def calculate_lines_time(lines_changed, weight)
    Math.log([lines_changed, 1].max) * 60 * weight
  end

  def calculate_files_time(file_count, weight)
    file_count * 30 * weight
  end

  def calculate_complexity_time(files, weight)
    calculate_complexity_factor(files) * 60 * weight
  end
end

# Module for logging related functionality
module PRLogging
  def log_results(estimate)
    log_changes(estimate)
    log_time_estimate(estimate)
  end

  private

  def log_changes(estimate)
    logger.info "Files changed: #{estimate[:files_count]}"
    logger.info "Lines added: #{estimate[:additions]}"
    logger.info "Lines deleted: #{estimate[:deletions]}"
  end

  def log_time_estimate(estimate)
    logger.info "Estimated review time: #{format_time(estimate[:time])}"
    logger.info "Applied label: #{estimate[:label]}"
  end

  def format_time(seconds)
    if seconds < 60
      "#{seconds.round} seconds"
    elsif seconds < 3600
      "#{(seconds / 60.0).round} minutes"
    else
      hours = (seconds / 3600.0).floor
      mins = ((seconds % 3600) / 60.0).round
      "#{hours}h #{mins}m"
    end
  end
end

# PRReviewTimeEstimator handles the estimation of pull request review times
# by analyzing the changes, complexity, and file types involved in the PR.
# It interacts with GitHub's API to fetch PR data and apply labels based on
# the estimated review duration.
class PRReviewTimeEstimator
  include PRComplexityCalculator
  include PRTimeCalculator
  include PRLogging

  attr_reader :client, :repository, :pr_number, :config, :logger

  class EstimatorError < StandardError; end

  def initialize(github_token, repository_name, pull_request_number, logger: default_logger)
    validate_inputs(github_token, repository_name, pull_request_number)
    setup_client(github_token)
    @repository = repository_name
    @pr_number = pull_request_number.to_i
    @logger = logger
    @config = Config.load( logger, ENV['CONFIG_PATH'] || './.pr-review-config.yml')
    logger.info "Initializing PR Review Time Estimator for #{repository_name}##{pull_request_number}"
  end

  def run
    data = collect_pr_data
    estimate = calculate_estimates(data)
    apply_results(estimate)
    create_response(estimate)
  rescue Octokit::Error => e
    logger.error "GitHub API error: #{e.message}"
    raise EstimatorError, "Failed to process PR: #{e.message}"
  end

  private

  def validate_inputs(token, repository, pr_number)
    errors = []
    errors << 'Missing GITHUB_TOKEN' if token.nil? || token.strip.empty?
    errors << 'Missing REPOSITORY' if repository.nil? || repository.strip.empty?
    errors << 'Missing PR_NUMBER' if pr_number.nil?
    raise EstimatorError, errors.join(', ') if errors.any?
  end

  def setup_client(token)
    @client = Octokit::Client.new(access_token: token)
    @client.user # Validate token
  rescue Octokit::Unauthorized => e
    raise EstimatorError, "Invalid GitHub token: #{e.message}"
  end

  def collect_pr_data
    {
      pr: client.pull_request(repository, pr_number),
      files: client.pull_request_files(repository, pr_number)
    }
  end

  def calculate_estimates(data)
    time_estimate = calculate_review_time(data[:pr], data[:files])
    {
      time: time_estimate,
      label: determine_label(time_estimate),
      files_count: data[:files].length,
      additions: data[:pr].additions,
      deletions: data[:pr].deletions
    }
  end

  def determine_label(time)
    "review-time: #{format_time(time)}"
  end

  def apply_results(estimate)
    ensure_label_exists(estimate[:label])
    client.add_labels_to_an_issue(repository, pr_number, [estimate[:label]])
    log_results(estimate)
  end

  def ensure_label_exists(label)
    color = label_color(label)
    client.add_label(repository, label, color)
  rescue Octokit::UnprocessableEntity => e
    logger.debug "Label already exists: #{e.message}"
  end

  def label_color(label)
    minutes = extract_minutes_from_label(label)

    quick_limit = (config['time_thresholds']['quick'] / 60.0).ceil
    standard_limit = (config['time_thresholds']['standard'] / 60.0).ceil

    case minutes
    when 0...quick_limit
      '2ecc71'  # Green
    when quick_limit...standard_limit
      'f1c40f'  # Yellow
    else
      'e74c3c'  # Red
    end
  end

  def extract_minutes_from_label(label)
    if label =~ /(\d+)\s*minutes?/
      $1.to_i
    elsif label =~ /(\d+)h\s*(\d+)m/
      $1.to_i * 60 + $2.to_i
    elsif label =~ /(\d+)h/
      $1.to_i * 60
    elsif label =~ /(\d+)\s*seconds?/
      ($1.to_i / 60.0).ceil
    else
      15 # fallback default
    end
  end

  def create_response(estimate)
    {
      pr_number: @pr_number,
      estimate_seconds: estimate[:time].round,
      label: estimate[:label]
    }
  end
end

# Main execution
begin
  logger = default_logger

  # Get required environment variables
  token = ENV['GITHUB_TOKEN']
  repository = ENV['REPOSITORY']
  pr_number = ENV['PR_NUMBER']

  # For GitHub Actions
  if ENV['GITHUB_EVENT_PATH'] && !pr_number
    event_data = JSON.parse(File.read(ENV['GITHUB_EVENT_PATH']))
    pr_number = event_data['pull_request']['number'] if event_data['pull_request']
    repository ||= ENV['GITHUB_REPOSITORY']
  end

  # For Buildkite
  if ENV['BUILDKITE_PULL_REQUEST'] && ENV['BUILDKITE_PULL_REQUEST'] != 'false' && !pr_number
    pr_number = ENV['BUILDKITE_PULL_REQUEST']
    repository ||= ENV['BUILDKITE_REPO'].gsub(/.*:/, '').gsub(/\.git$/, '')
  end

  # Validate inputs
  unless token && repository && pr_number
    logger.error 'Missing required environment variables.'
    logger.error 'Required: GITHUB_TOKEN, REPOSITORY, PR_NUMBER'
    exit 1
  end

  # Run the estimator
  estimator = PRReviewTimeEstimator.new(token, repository, pr_number)
  estimator.run
rescue StandardError => e
  logger.error "Error: #{e.message}"
  logger.error e.backtrace.join("\n") if ENV['DEBUG']
  exit 1
end

