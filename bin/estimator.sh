#!/bin/bash
set -euo pipefail

bundle install

REPOSITORY=$REPOSITORY GITHUB_TOKEN=$GITHUB_TOKEN ruby estimate_pr_review_time.rb
