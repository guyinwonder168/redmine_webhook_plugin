#!/usr/bin/env bash
set -euo pipefail

#----------------------------------------
# Helper: Colored Output
#----------------------------------------
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

info()    { echo -e "${GREEN}==> $*${NC}"; }
warn()    { echo -e "${YELLOW}[!] $*${NC}"; }
error()   { echo -e "${RED}[ERROR] $*${NC}" >&2; }
section() { echo -e "\n${GREEN}============================================================================================================================================================ \
                    ${NC}\n$1\n${GREEN}============================================================================================================================================================${NC}"; }
closed()  { echo -e "\n${GREEN}------------------------------------------------------------------------------------------------------------------------------------------------------------${NC}\n"; }

PLUGIN_DIRNAME="${PLUGIN_DIRNAME:-redmine_webhook_plugin}"
PLUGIN_SRC_DIR="${PLUGIN_SRC_DIR:-}"
REDMINE_DIR="${REDMINE_DIR:-}"
CLONE_MODE=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_SRC_DIR="${PLUGIN_SRC_DIR:-${ROOT_DIR}}"
REQUIRE_TESTS="${REQUIRE_TESTS:-1}"
PLUGIN_DEST_DIR="${REDMINE_DIR}/plugins/${PLUGIN_DIRNAME}"

info "Plugin dirname: ${PLUGIN_DIRNAME}"
info "Plugin source: ${PLUGIN_SRC_DIR}"
info "PLUGIN_DEST_DIR: ${PLUGIN_DEST_DIR}"

if [ -z "${REDMINE_DIR}" ]; then
  CLONE_MODE=1
  REDMINE_REF="${REDMINE_REF:?Set REDMINE_DIR (prebaked/offline) or REDMINE_REF (clone mode)}"
  REDMINE_REPO_URL="${REDMINE_REPO_URL:-https://github.com/redmine/redmine.git}"
  REDMINE_DIR="${ROOT_DIR}/.tmp/redmine-${REDMINE_REF}"

  info "Redmine ref: ${REDMINE_REF}"
  info "Redmine repo: ${REDMINE_REPO_URL}"
  info "Redmine dir:  ${REDMINE_DIR}"

  rm -rf "${REDMINE_DIR}"
  mkdir -p "${REDMINE_DIR}"
  git clone --depth 1 --branch "${REDMINE_REF}" "${REDMINE_REPO_URL}" "${REDMINE_DIR}"
else
  info "Redmine dir:  ${REDMINE_DIR} (prebaked)"
fi

if [ ! -d "${REDMINE_DIR}" ]; then
  error "ERROR: REDMINE_DIR does not exist: ${REDMINE_DIR}" >&2
  exit 1
fi

cd "${REDMINE_DIR}"

if [ ! -f "${PLUGIN_DEST_DIR}/init.rb" ]; then
  error "ERROR: plugin init.rb not found at ${PLUGIN_DEST_DIR}/init.rb" >&2
  exit 1
fi

PLUGIN_TEST_COUNT=0
if [ -d "${PLUGIN_DEST_DIR}/test" ]; then
  PLUGIN_TEST_COUNT="$(find "${PLUGIN_DEST_DIR}/test" -type f -name "*_test.rb" | wc -l | tr -d ' ')"
fi

info "Plugin test files: ${PLUGIN_TEST_COUNT}"
if [ "${REQUIRE_TESTS}" = "1" ] && [ "${PLUGIN_TEST_COUNT}" -eq 0 ]; then
  error "ERROR: No *_test.rb found under ${PLUGIN_DEST_DIR}/test (CI would report 0 runs)." >&2
  exit 1
fi

if [ -n "${BUNDLE_PATH:-}" ]; then
  bundle config set path "${BUNDLE_PATH}"
fi

if [ "${CLONE_MODE}" = "1" ]; then
  bundle install --jobs "${BUNDLE_JOBS:-4}" --retry "${BUNDLE_RETRY:-3}"
else
  info "Checking gems (offline/prebaked mode)…"
  bundle check || {
    error "ERROR: bundle check failed." >&2
    error "Ensure the CI image contains Redmine dependencies (gems) already installed for /redmine." >&2
    exit 1
  }
fi

#bundle exec rake db:drop db:create db:migrate RAILS_ENV=test
#bundle exec rake redmine:plugins:migrate RAILS_ENV=test

info "Preparing test database (core migrations)"
bundle exec rake db:drop db:create RAILS_ENV=test
bundle exec rake db:migrate RAILS_ENV=test

info "Running plugin migrations"
bundle exec rake redmine:plugins:migrate RAILS_ENV=test

info "Running plugin tests (if available)…"
if bundle exec rake -T | grep -q "^rake redmine:plugins:test"; then
  OUTPUT_FILE="$(mktemp)"
  bundle exec rake redmine:plugins:test NAME="${PLUGIN_DIRNAME}" RAILS_ENV=test | tee "${OUTPUT_FILE}"
elif bundle exec rake -T | grep -q "^rake test:plugins"; then
  OUTPUT_FILE="$(mktemp)"
  bundle exec rake test:plugins PLUGIN="${PLUGIN_DIRNAME}" RAILS_ENV=test | tee "${OUTPUT_FILE}"
else
  warn "No plugin test task found; doing a minimal environment boot check."
  bundle exec ruby -e "require './config/environment'; puts \"Loaded Redmine #{Redmine::VERSION}\""
  OUTPUT_FILE=""
fi

if [ "${REQUIRE_TESTS}" = "1" ] && [ -n "${OUTPUT_FILE}" ] && grep -qE "^[[:space:]]*0 runs," "${OUTPUT_FILE}"; then
  error "ERROR: No tests were executed (0 runs). Ensure plugin tests are discoverable by Redmine's plugin test task." >&2
  exit 1
fi

