# Dockerfile for PR Review Time Estimator
FROM ruby:3.4-slim

# Set up environment
ENV APP_HOME="/app"
WORKDIR $APP_HOME

# Install dependencies for git diff parsing and system dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install bundler
RUN gem install bundler -v 2.4.10

# Copy gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copy application code
COPY . .

# Make scripts executable
RUN chmod +x ./estimate_pr_review_time.rb

# Set the default command
ENTRYPOINT ["bin/estimator.sh"]
