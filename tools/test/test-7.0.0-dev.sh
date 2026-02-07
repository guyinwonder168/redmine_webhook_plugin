#!/usr/bin/env bash
# Test runner for Redmine 7.0.0-dev (Rails 8.0, trunk)
#
# Note: Uses db:schema:load instead of db:migrate for speed.
# The sqlite3 commands ensure schema_migrations table exists for plugin migrations,
# which is needed because db:schema:load doesn't create it the same way db:migrate does.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REDMINE_DIR="${REDMINE_DIR:-${PLUGIN_ROOT}/.redmine-test/redmine-7.0.0-dev}"
PLUGIN_DIR="${PLUGIN_DIR:-${PLUGIN_ROOT}}"
BUNDLE_DIR="${BUNDLE_DIR:-${PLUGIN_ROOT}/.bundle-cache/7.0.0-dev}"
IMAGE="redmine-dev:7.0.0-dev"
LOG_DIR="${PLUGIN_ROOT}/logs"
LOG_FILE="${LOG_DIR}/run-test-7.0.0-dev.log"
ESC=$'\033'

mkdir -p "${BUNDLE_DIR}"
mkdir -p "${LOG_DIR}"

podman run --rm -it \
  -v "${REDMINE_DIR}:/redmine:rw" \
  -v "${PLUGIN_DIR}:/redmine/plugins/redmine_webhook_plugin:rw" \
  -v "${BUNDLE_DIR}:/bundle:rw" \
  -e BUNDLE_PATH=/bundle \
  -e BUNDLE_APP_CONFIG=/bundle/.bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  -e TESTOPTS \
  "${IMAGE}" \
  bash -lc 'set -euo pipefail; cd /redmine; \
    BUNDLER_VERSION=2.5.11; \
    BUNDLE_CMD=(bundle); \
    if [ -n "${BUNDLER_VERSION}" ]; then \
      if ! gem list -i bundler -v "${BUNDLER_VERSION}" >/dev/null 2>&1; then \
        gem install bundler -v "${BUNDLER_VERSION}"; \
      fi; \
      BUNDLE_CMD=(bundle "_${BUNDLER_VERSION}_"); \
    fi; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! "${BUNDLE_CMD[@]}" check; then "${BUNDLE_CMD[@]}" install --jobs 4 --retry 3; fi; \
    "${BUNDLE_CMD[@]}" exec rake db:drop RAILS_ENV=test || true; \
    "${BUNDLE_CMD[@]}" exec rake db:create db:schema:load RAILS_ENV=test; \
    sqlite3 db/redmine_test.sqlite3 "CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR(255) NOT NULL UNIQUE PRIMARY KEY);" 2>/dev/null || true; \
    sqlite3 db/redmine_test.sqlite3 "CREATE UNIQUE INDEX IF NOT EXISTS unique_schema_migrations ON schema_migrations (version);" 2>/dev/null || true; \
    "${BUNDLE_CMD[@]}" exec rake redmine:plugins:migrate RAILS_ENV=test; \
    TESTOPTS="--verbose" "${BUNDLE_CMD[@]}" exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test' \
  2>&1 | tee >(sed -E "s/${ESC}\\[[0-9;]*[[:alpha:]]//g" > "$LOG_FILE")
