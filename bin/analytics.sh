#!/bin/bash
set -euo pipefail

bundle install

REPOSITORY=$REPOSITORY GITHUB_TOKEN=$GITHUB_TOKEN ruby analyze_pr_review_times.rb
