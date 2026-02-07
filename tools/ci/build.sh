#!/bin/bash
set -e

# Usage: ./build.sh 6.1.0
REDMINE_VERSION="$1"

if [[ -z "$REDMINE_VERSION" ]]; then
  echo "Usage: $0 <redmine-version>"
  echo "Example: $0 6.1.0"
  exit 1
fi

# Determine Ruby version and Minitest version based on Redmine version
case "$REDMINE_VERSION" in
  5.*)
    RUBY_VERSION="3.2"
    MINITEST_GEM="minitest"
    MINITEST_VER="~> 5.0"
    ;;
  6.*)
    RUBY_VERSION="3.4"
    MINITEST_GEM="minitest-rails"
    MINITEST_VER=">= 6.1"
    ;;
  *)
    echo "Unsupported Redmine version: $REDMINE_VERSION"
    exit 1
    ;;
esac

# Docker image name
IMAGE_NAME="registry.example.com/devops/redmine-plug:${REDMINE_VERSION}"

# Generate a temporary Dockerfile
DOCKERFILE=$(mktemp)

cat > "$DOCKERFILE" <<EOF
# Base Ruby image
# Redmine 5.1.x officially supports Ruby 2.7 → 3.2
# Redmine 6.1.x officially supports Ruby 3.2, 3.3, 3.4
FROM ruby:${RUBY_VERSION}

# Require Ruby logger before Rails loads ActiveSupport
ENV RUBYOPT="-rlogger"

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    sqlite3 \\
    libsqlite3-dev \\
    build-essential \\
    && rm -rf /var/lib/apt/lists/*

# Create Redmine directory
RUN mkdir -p /redmine

# Copy Redmine tarball (assumes it exists in current dir)
COPY redmine-${REDMINE_VERSION}.tar.gz /redmine/

# Extract Redmine
RUN tar xvf /redmine/redmine-${REDMINE_VERSION}.tar.gz --strip-components=1 -C /redmine

# Set working directory
WORKDIR /redmine

# Install bundler
RUN gem install bundler

# Pin Minitest for Redmine version compatibility
RUN echo "gem '${MINITEST_GEM}', '${MINITEST_VER}'" >> /redmine/Gemfile

# Create test database configuration
RUN mkdir -p /redmine/config
RUN printf "test:\\n  adapter: sqlite3\\n  database: db/redmine_test.sqlite3\\n  pool: 5\\n  timeout: 5000\\n" > /redmine/config/database.yml

# Install gems
RUN bundle config set without 'development' \\
 && bundle install \\
 && bundle check

# Final working directory
WORKDIR /redmine/plugins
EOF

# Build Docker image
docker build -f "$DOCKERFILE" -t "$IMAGE_NAME" .

# Clean up
rm -f "$DOCKERFILE"

echo "Docker image built: $IMAGE_NAME"