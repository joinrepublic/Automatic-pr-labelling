# Dockerfile for PR Review Analytics
FROM ruby:3.4-slim

# Set up environment
ENV APP_HOME="/app"
WORKDIR $APP_HOME

# Install system dependencies
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

# Install additional gems for data analysis
RUN gem install descriptive_statistics terminal-table

# Copy application code
COPY . .

# Make scripts executable
RUN chmod +x ./analyze_pr_review_times.rb

# Set the default command
ENTRYPOINT ["bin/analytics.sh"]
