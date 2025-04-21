#!/bin/bash
set -euo pipefail

bundle install

bundle exec ruby estimate_pr_review_time.rb
