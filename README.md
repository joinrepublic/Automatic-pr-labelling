# Automatic PR Labelling
This repository contains two dockerized Ruby applications for managing and analyzing GitHub Pull Request review times:
1. PR Review Time Estimator - Automatically estimates review time for new PRs and applies appropriate labels
2. PR Review Analytics - Calculates average review times for closed PRs to measure process improvements
Both tools work together to help teams optimize their code review process by providing realistic time expectations and measuring progress.

## Overview
The Automatic PR Labelling analyzes various metrics of a Pull Request (size, complexity, files changed, etc.) to estimate how long a review will take. It then automatically applies one of the following labels:
- review-time: <5mins - Quick reviews
- review-time: ~30mins - Standard reviews
- review-time: >30mins - In-depth reviews requiring significant time
The Automatic PR Labelling helps measure the impact of this labeling system by calculating the actual time spent on reviews before and after implementation.

## Installation

### Prerequisites
- Docker
- GitHub access token with repo permissions
- Ruby 3.0+ (only if running locally without Docker)

### Setup
1. Clone this repository:
```shell
  git clone https://github.com/joinrepublic/Automatic-pr-labelling.git
  cd Automatic-pr-labelling
```
2. Build the Docker images:
```shell
    docker build -t pr-analytics -f docker/analytics/Dockerfile .
```
3. Set up your environment variables:
```shell
    cp .env.example .env
    # Edit .env file with your GitHub credentials
```

## Usage
### PR Review Analytics
#### Running locally with Docker
```shell
docker run --rm \
  -e GITHUB_TOKEN=your_token \
  -e REPOSITORY=owner/repo \
  -e DATE_RANGE=30d \
  pr-analytics
```

#### Running locally without Docker
```shell
$ GITHUB_TOKEN=your_token REPOSITORY=owner/repo bundle exec ruby analyze_pr_review_times.rb
```
 An example output would be
```shell
I, [2025-04-14T14:56:18.215478 #50810]  INFO -- : Successfully connected to GitHub API and found repository: joinrepublic/seedrs
I, [2025-04-14T14:56:18.215775 #50810]  INFO -- : Analyzing PRs closed since 2025-03-15
I, [2025-04-14T14:57:22.745211 #50810]  INFO -- : Found 110 PRs to analyze

----- GitHub PR Review Analytics for joinrepublic/seedrs -----
Analyzed 110 PRs closed in the last 30 days

Time to First Review:
  Average: 1d 17h
  Median: 11h 56m
  90th percentile: 4d 0h

Time to Merge:
  Average: 15d 11h
  Median: 4d 0h
  90th percentile: 47d 4h

Reviews per PR:
  Average: 3.4
  Maximum: 17
```

## Testing
### PR Review Analytics
#### Locally without Docker
```shell
$ GITHUB_TOKEN=your_token REPOSITORY=owner/repo bundle exec rspec
```
