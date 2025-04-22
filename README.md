# Automatic PR Labelling
This repository contains two dockerized Ruby applications for managing and analyzing GitHub Pull Request review times:
1. PR Review Time Estimator - Automatically estimates review time for new PRs and applies appropriate labels
2. PR Review Analytics - Calculates average review times for closed PRs to measure process improvements
Both tools work together to help teams optimize their code review process by providing realistic time expectations and measuring progress.

Further documentation is available [here](https://www.notion.so/republic/Pull-Request-Review-Time-Estimation-Algorithm-1dd86567bd75801d9763e3779a088ab7).

## Overview
The Automatic PR Labelling analyzes various metrics of a Pull Request (size, complexity, files changed, etc.) to estimate how long a review will take. It then automatically applies one of the following labels:
- review-time: <5mins - Quick reviews
- review-time: <15mins - Standard reviews
- review-time: >15mins - In-depth reviews requiring significant time

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
    docker build -t pr-estimator -f docker/estimator/Dockerfile .
```
3. Set up your environment variables:
```shell
    cp .env.example .env
    # Edit .env file with your GitHub credentials
```
4. Please make sure that you have the following environment variable defined:
  - `GITHUB_TOKEN`: a valid GitHub token that allows you access to the repo you want to run these analytics for;
  - `REPOSITORY`: the `owner/repo` on which you want to run these analytics;
  - `DATE_RANGE`: will default to `30d`, so need not to have it defined, but...

## Usage
### PR Review Estimator
The main use case of this estimator is to be run as part of a GitHub action whenever a pull request is done. Therefore we start by [ syill a work in progress ] an action from another repo invoquing this script.

But if you want to run it locally, with or without docker, please keep on reading the following subsections.

#### Running from another GitHub action

This is the most expected use case for this script: to run it as part of the PR action, from another repo.

```yaml
jobs:
  run-script:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repo B
        uses: actions/checkout@v4

      - name: Run PR review estimator from Repo A
        uses: joirepublic/Automatic-pr-labelling@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          repository: your-org/repo-b
          pr_number: ${{ github.event.pull_request.number }}
          config_path: .pr-review-config.yml
```

#### Running locally without Docker
To run the estimator script without using docker you shoud execute the following:

```shell
$ bin/estimator
```

#### Example output
An example output is be

```shell
GITHUB_TOKEN=$GITHUB_TOKEN REPOSITORY=$REPOSITORY PR_NUMBER=16810 bin/estimator.sh
Bundle complete! 11 Gemfile dependencies, 45 gems now installed.
Bundled gems are installed into `./vendor`
I, [2025-04-21T10:15:33.433015 #77307]  INFO -- : Initializing PR Review Time Estimator for owner/repo#xyz
I, [2025-04-21T10:15:35.662019 #77307]  INFO -- : Files changed: 2
I, [2025-04-21T10:15:35.662106 #77307]  INFO -- : Lines added: 5
I, [2025-04-21T10:15:35.662121 #77307]  INFO -- : Lines deleted: 5
I, [2025-04-21T10:15:35.662140 #77307]  INFO -- : Estimated review time: 3 minutes
I, [2025-04-21T10:15:35.662152 #77307]  INFO -- : Applied label: review-time: 3 minutes
```

### PR Review Analytics
The analytics script is a helper tool for those that want to gather data on if indeed labelling PRs according to an estimate of the time the PR will take to be reviewed helps in shortenning that time.

We support both running with Docker and without it.

#### Running locally with Docker
To run the analytics script with docker (after having built it -- see above) you shoud execute the follwoing:

```shell
docker run --rm \
  -e GITHUB_TOKEN=your_token \
  -e REPOSITORY=owner/repo \
  -e DATE_RANGE=30d \
  pr-analytics
```

#### Running locally without Docker
To run the analytics script without using docker  you shoud execute the following:

```shell
$ bin/analytics.sh
```

#### Example output
An example output is be

```shell
I, [2025-04-14T14:56:18.215478 #50810]  INFO -- : Successfully connected to GitHub API and found repository: owner/repo
I, [2025-04-14T14:56:18.215775 #50810]  INFO -- : Analyzing PRs closed since 2025-03-15
I, [2025-04-14T14:57:22.745211 #50810]  INFO -- : Found 110 PRs to analyze

----- GitHub PR Review Analytics for owner/repo -----
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
