#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REDMINE_DIR="${REDMINE_DIR:-${PLUGIN_ROOT}/.redmine-test/redmine-5.1.10}"
PLUGIN_DIR="${PLUGIN_DIR:-${PLUGIN_ROOT}}"
BUNDLE_DIR="${BUNDLE_DIR:-${PLUGIN_ROOT}/.bundle-cache/5.1.10}"
IMAGE="redmine-dev:5.1.10"
LOG_DIR="${PLUGIN_ROOT}/logs"
LOG_FILE="${LOG_DIR}/run-test-5.1.10.log"
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
    BUNDLER_VERSION=2.4.10; \
    BUNDLE_CMD=(bundle); \
    if [ -n "${BUNDLER_VERSION}" ]; then \
      if ! gem list -i bundler -v "${BUNDLER_VERSION}" >/dev/null 2>&1; then \
        gem install bundler -v "${BUNDLER_VERSION}"; \
      fi; \
      BUNDLE_CMD=(bundle "_${BUNDLER_VERSION}_"); \
    fi; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! "${BUNDLE_CMD[@]}" check; then "${BUNDLE_CMD[@]}" install --jobs 4 --retry 3; fi; \
    "${BUNDLE_CMD[@]}" exec rails db:environment:set RAILS_ENV=test; \
    "${BUNDLE_CMD[@]}" exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    "${BUNDLE_CMD[@]}" exec rake redmine:plugins:migrate RAILS_ENV=test; \
    "${BUNDLE_CMD[@]}" exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test' \
  2>&1 | tee >(sed -E "s/${ESC}\\[[0-9;]*[[:alpha:]]//g" > "$LOG_FILE")
