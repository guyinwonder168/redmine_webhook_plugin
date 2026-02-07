#!/usr/bin/env bash
# Unified Redmine Plugin Integration Test Runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="${VERSION:-}"
REDMINE_ROOT="${REDMINE_ROOT:-}"
USE_PODMAN="${USE_PODMAN:-1}"
VERBOSE="${VERBOSE:-0}"
TESTFILE="${TESTFILE:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

show_usage() {
    echo "Usage: VERSION=5.1.0 $0"
    echo "       VERSION=all $0"
    echo "       TESTFILE=webhook_integration_test VERSION=5.1.0 $0"
    echo "       TESTFILE=integration/webhook_integration_test VERSION=5.1.0 $0"
}

parse_args() {
    local VERSION_FROM_ARG=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --all)
                VERSION="all"
                VERSION_FROM_ARG=1
                ;;
            --verbose|-v)
                VERBOSE=1
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -* )
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ "$VERSION_FROM_ARG" -eq 1 ]; then
                    error "Multiple versions provided: $VERSION and $1"
                    show_usage
                    exit 1
                fi
                VERSION="$1"
                VERSION_FROM_ARG=1
                ;;
        esac
        shift
    done
}

use_verbose() {
    case "${VERBOSE}" in
        1|true|TRUE|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

use_podman() {
    case "${USE_PODMAN}" in
        0|false|FALSE|no|NO)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

testopts_for_version() {
    local VERSION="$1"

    if use_verbose || [ "$VERSION" = "6.1.0" ] || [ "$VERSION" = "7.0.0-dev" ]; then
        printf '%s' '--verbose'
    fi
}

integration_test_path() {
    local TESTFILE_NAME

    if [ -z "$TESTFILE" ]; then
        TESTFILE_NAME="webhook_integration_test"
    else
        TESTFILE_NAME="${TESTFILE%.rb}"
        TESTFILE_NAME="${TESTFILE_NAME#integration/}"
    fi

    printf '%s' "plugins/redmine_webhook_plugin/test/integration/${TESTFILE_NAME}.rb"
}

bundler_version_for() {
    case "$1" in
        5.1.0|5.1.10)
            echo "2.4.10"
            ;;
        6.1.0|7.0.0-dev)
            echo "2.5.11"
            ;;
        *)
            echo ""
            ;;
    esac
}

detect_redmine_dir() {
    local VERSION="$1"
    local REDMINE_ROOT="${REDMINE_ROOT:-}"

    info "Detecting Redmine ${VERSION} installation..." >&2

    if [ -n "$REDMINE_ROOT" ] && [ -d "$REDMINE_ROOT" ]; then
        info "Using REDMINE_ROOT override: $REDMINE_ROOT" >&2
        echo "$REDMINE_ROOT"
        return 0
    fi

    if [ -d "${PLUGIN_ROOT}/../redmine-${VERSION}" ]; then
        local PARENT_DIR="${PLUGIN_ROOT}/../redmine-${VERSION}"
        info "Found Redmine ${VERSION} in parent directory: $PARENT_DIR" >&2
        echo "$PARENT_DIR"
        return 0
    fi

    if [ -d "${PLUGIN_ROOT}/.redmine-test/redmine-${VERSION}" ]; then
        local CACHE_DIR="${PLUGIN_ROOT}/.redmine-test/redmine-${VERSION}"
        info "Found Redmine ${VERSION} in local cache: $CACHE_DIR" >&2
        echo "$CACHE_DIR"
        return 0
    fi

    error "Redmine ${VERSION} not found locally. Run tools/test/run-test.sh to download."
    exit 1
}

resolve_versions() {
    local VERSION_INPUT="$1"

    if [ "$VERSION_INPUT" = "all" ] || [ "$VERSION_INPUT" = "ALL" ]; then
        echo "5.1.0 5.1.10 6.1.0 7.0.0-dev"
        return 0
    fi

    if [[ "$VERSION_INPUT" == *","* ]]; then
        echo "$VERSION_INPUT" | tr ',' ' '
        return 0
    fi

    echo "$VERSION_INPUT"
}

run_podman_integration() {
    local VERSION="$1"
    local REDMINE_DIR
    local TEST_PATH
    local BUNDLE_DIR
    local LOG_DIR
    local LOG_FILE
    local ESC
    local BUNDLER_VERSION
    local DB_ENV_CMD
    local DB_SETUP_CMD
    local TESTOPTS_VALUE
    local CONTAINER_CMD

    REDMINE_DIR="$(detect_redmine_dir "$VERSION")"
    TEST_PATH="$(integration_test_path)"

    if [ ! -f "${PLUGIN_ROOT}/test/integration/${TEST_PATH##*/}" ]; then
        error "Integration test file not found: ${PLUGIN_ROOT}/test/integration/${TEST_PATH##*/}"
        exit 1
    fi

    BUNDLE_DIR="${PLUGIN_ROOT}/.bundle-cache/${VERSION}"
    LOG_DIR="${PLUGIN_ROOT}/logs"
    LOG_FILE="${LOG_DIR}/run-integration-test-${VERSION}.log"
    ESC=$'\033'

    mkdir -p "$BUNDLE_DIR"
    mkdir -p "$LOG_DIR"

    BUNDLER_VERSION="$(bundler_version_for "$VERSION")"
    TESTOPTS_VALUE="$(testopts_for_version "$VERSION")"

    if [ "$VERSION" = "5.1.10" ]; then
        DB_ENV_CMD='"${BUNDLE_CMD[@]}" exec rails db:environment:set RAILS_ENV=test || true'
    else
        DB_ENV_CMD='"${BUNDLE_CMD[@]}" exec rake db:environment:set RAILS_ENV=test || true'
    fi

    if [ "$VERSION" = "6.1.0" ] || [ "$VERSION" = "7.0.0-dev" ]; then
        DB_SETUP_CMD='"${BUNDLE_CMD[@]}" exec rake db:drop RAILS_ENV=test || true; "${BUNDLE_CMD[@]}" exec rake db:create db:schema:load RAILS_ENV=test; sqlite3 db/redmine_test.sqlite3 "CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR(255) NOT NULL UNIQUE PRIMARY KEY);" 2>/dev/null || true; sqlite3 db/redmine_test.sqlite3 "CREATE UNIQUE INDEX IF NOT EXISTS unique_schema_migrations ON schema_migrations (version);" 2>/dev/null || true;'
    else
        DB_SETUP_CMD='"${BUNDLE_CMD[@]}" exec rake db:drop db:create db:migrate RAILS_ENV=test;'
    fi

    CONTAINER_CMD=$(cat <<EOF
set -euo pipefail
cd /redmine
BUNDLER_VERSION="${BUNDLER_VERSION}"
BUNDLE_CMD=(bundle)
if [ -n "\${BUNDLER_VERSION}" ]; then
  if ! gem list -i bundler -v "\${BUNDLER_VERSION}" >/dev/null 2>&1; then
    gem install bundler -v "\${BUNDLER_VERSION}"
  fi
  BUNDLE_CMD=(bundle "_\${BUNDLER_VERSION}_")
fi
printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml
if ! "\${BUNDLE_CMD[@]}" check; then "\${BUNDLE_CMD[@]}" install --jobs 4 --retry 3; fi
${DB_ENV_CMD}
${DB_SETUP_CMD}
"\${BUNDLE_CMD[@]}" exec rake redmine:plugins:migrate RAILS_ENV=test
if [ -n "${TESTOPTS_VALUE}" ]; then
  export TESTOPTS="${TESTOPTS_VALUE}"
fi
"\${BUNDLE_CMD[@]}" exec ruby -Ilib:test "${TEST_PATH}" -v
EOF
)

    info "Running podman integration test for Redmine ${VERSION}: ${TEST_PATH}"
    info "Using Redmine directory: ${REDMINE_DIR}"

    podman run --rm -it \
      -v "${REDMINE_DIR}:/redmine:rw" \
      -v "${PLUGIN_ROOT}:/redmine/plugins/redmine_webhook_plugin:rw" \
      -v "${BUNDLE_DIR}:/bundle:rw" \
      -e BUNDLE_PATH=/bundle \
      -e BUNDLE_APP_CONFIG=/bundle/.bundle \
      -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
      "redmine-dev:${VERSION}" \
      bash -lc "${CONTAINER_CMD}" \
      2>&1 | tee >(sed -E "s/${ESC}\[[0-9;]*[[:alpha:]]//g" > "$LOG_FILE")
}

run_host_integration() {
    local VERSION="$1"
    local REDMINE_DIR
    local TEST_PATH
    local LOG_FILE
    local TESTOPTS_ENV=()
    local TESTOPTS_VALUE

    REDMINE_DIR="$(detect_redmine_dir "$VERSION")"
    TEST_PATH="$(integration_test_path)"
    LOG_FILE="${PLUGIN_ROOT}/logs/run-integration-test-${VERSION}.log"

    if [ ! -f "${REDMINE_DIR}/${TEST_PATH}" ]; then
        error "Integration test file not found: ${REDMINE_DIR}/${TEST_PATH}"
        exit 1
    fi

    TESTOPTS_VALUE="$(testopts_for_version "$VERSION")"
    if [ -n "$TESTOPTS_VALUE" ]; then
        TESTOPTS_ENV=(TESTOPTS="$TESTOPTS_VALUE")
    fi

    info "Running host integration test for Redmine ${VERSION}: ${TEST_PATH}"
    info "Using Redmine directory: ${REDMINE_DIR}"

    (cd "$REDMINE_DIR" && "${TESTOPTS_ENV[@]}" bundle exec ruby -Ilib:test "${TEST_PATH}" -v 2>&1 | tee "$LOG_FILE")
}

main() {
    parse_args "$@"

    if [ -z "$VERSION" ]; then
        error "VERSION must be set"
        show_usage
        exit 1
    fi

    local VERSIONS
    VERSIONS="$(resolve_versions "$VERSION")"

    if use_podman; then
        info "Starting integration test runner (podman) for Redmine: ${VERSIONS}"
    else
        info "Starting integration test runner (host) for Redmine: ${VERSIONS}"
    fi

    for V in $VERSIONS; do
        if use_podman; then
            run_podman_integration "$V"
        else
            run_host_integration "$V"
        fi
    done

    success "All integration tests completed successfully"
}

main "$@"
