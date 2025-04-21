#!/bin/sh
set -e

export GITHUB_TOKEN="${INPUT_GITHUB_TOKEN}"
export GITHUB_REPOSITORY="${GITHUB_REPOSITORY}"
export GITHUB_EVENT_PATH="${GITHUB_EVENT_PATH}"

ruby estimate_pr_review_time.rb
