# spec/spec_helper.rb
require 'rspec'
require_relative '../analyze_pr_review_times'

RSpec.configure do |config|
  config.order = :defined
  config.color = true
  config.formatter = :documentation
end
