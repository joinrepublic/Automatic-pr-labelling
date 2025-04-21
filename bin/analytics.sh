#!/bin/bash
set -euo pipefail

bundle install

bundle exec ruby analyze_pr_review_times.rb
