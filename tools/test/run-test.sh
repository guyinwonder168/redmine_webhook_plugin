#!/usr/bin/env bash
# Unified Redmine Plugin Test Runner
# Supports multiple Redmine versions and environments

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="${VERSION:-}"
REDMINE_ROOT="${REDMINE_ROOT:-}"
USE_PODMAN="${USE_PODMAN:-1}"
VERBOSE="${VERBOSE:-0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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
    echo "       $0 5.1.0"
    echo "       $0 --all"
    echo "       $0 --all --verbose"
    echo "       USE_PODMAN=0 $0 5.1.0"
    echo "       VERBOSE=1 $0 6.1.0"
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

testopts_for_version() {
    local VERSION="$1"

    if use_verbose || [ "$VERSION" = "6.1.0" ] || [ "$VERSION" = "7.0.0-dev" ]; then
        printf '%s' '--verbose'
    fi
}

testfile_path() {
    if [ -z "${TESTFILE:-}" ]; then
        return 1
    fi

    local TESTFILE_NAME="${TESTFILE%.rb}"
    printf '%s' "plugins/redmine_webhook_plugin/test/unit/${TESTFILE_NAME}.rb"
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

bundler_version_for() {
    case "$1" in
        5.1.0|5.1.10)
            echo "2.4.10"
            ;;
        6.1.0)
            echo "2.5.11"
            ;;
        7.0.0-dev)
            echo "2.5.11"
            ;;
        *)
            echo ""
            ;;
    esac
}

setup_bundler_cmd() {
    local VERSION="$1"
    local BUNDLER_VERSION

    BUNDLER_VERSION="$(bundler_version_for "$VERSION")"
    BUNDLE_CMD=(bundle)

    if [ -z "$BUNDLER_VERSION" ]; then
        if ! command -v bundle >/dev/null 2>&1; then
            error "Bundler not found. Install Ruby/Bundler or run tools/test/test-${VERSION}.sh (podman)."
            exit 1
        fi
        return 0
    fi

    if ! command -v gem >/dev/null 2>&1; then
        error "RubyGems (gem) is unavailable. Install Ruby/Bundler or run tools/test/test-${VERSION}.sh (podman)."
        exit 1
    fi

    if ! gem list -i bundler -v "$BUNDLER_VERSION" >/dev/null 2>&1; then
        if [ "${ALLOW_HOST_GEM_INSTALL:-}" != "1" ]; then
            error "Bundler ${BUNDLER_VERSION} is not installed. To avoid host changes, run tools/test/test-${VERSION}.sh (podman)."
            info "Alternatively, set ALLOW_HOST_GEM_INSTALL=1 to install Bundler on the host."
            exit 1
        fi
        info "Installing Bundler ${BUNDLER_VERSION}..."
        if ! gem install bundler -v "$BUNDLER_VERSION"; then
            error "Bundler install failed. Consider tools/test/test-${VERSION}.sh (podman)."
            exit 1
        fi
    fi

    BUNDLE_CMD=(bundle "_${BUNDLER_VERSION}_")
}

# Detect Redmine installation directory
detect_redmine_dir() {
    local VERSION="$1"
    local REDMINE_ROOT="${REDMINE_ROOT:-}"

    info "Detecting Redmine ${VERSION} installation..." >&2

    # Priority 1: Environment variable (user override)
    if [ -n "$REDMINE_ROOT" ] && [ -d "$REDMINE_ROOT" ]; then
        info "Using REDMINE_ROOT override: $REDMINE_ROOT" >&2
        echo "$REDMINE_ROOT"
        return 0
    fi

    # Priority 2: Parent directory (backwards compatible)
    if [ -d "${PLUGIN_ROOT}/../redmine-${VERSION}" ]; then
        local PARENT_DIR="${PLUGIN_ROOT}/../redmine-${VERSION}"
        info "Found Redmine ${VERSION} in parent directory: $PARENT_DIR" >&2
        echo "$PARENT_DIR"
        return 0
    fi

    # Priority 3: Local cache
    if [ -d "${PLUGIN_ROOT}/.redmine-test/redmine-${VERSION}" ]; then
        local CACHE_DIR="${PLUGIN_ROOT}/.redmine-test/redmine-${VERSION}"
        info "Found Redmine ${VERSION} in local cache: $CACHE_DIR" >&2
        echo "$CACHE_DIR"
        return 0
    fi

    # Priority 4: Auto-download
    info "Redmine ${VERSION} not found locally, downloading..." >&2
    download_redmine "$VERSION" "${PLUGIN_ROOT}/.redmine-test/redmine-${VERSION}" >&2
    echo "${PLUGIN_ROOT}/.redmine-test/redmine-${VERSION}"
    return 0
}

# Download Redmine from official source
download_redmine() {
    local VERSION="$1"
    local DEST_DIR="$2"

    info "Downloading Redmine ${VERSION}..."

    mkdir -p "$(dirname "$DEST_DIR")"

    # Download tarball
    local URL="https://www.redmine.org/releases/redmine-${VERSION}.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -L "$URL" | tar xz -C "$(dirname "$DEST_DIR")"
        mv "$(dirname "$DEST_DIR")/redmine-${VERSION}" "$DEST_DIR"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$URL" | tar xz -C "$(dirname "$DEST_DIR")"
        mv "$(dirname "$DEST_DIR")/redmine-${VERSION}" "$DEST_DIR"
    else
        error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi

    success "Downloaded Redmine ${VERSION} to ${DEST_DIR}"
}

# Setup bundle cache directory
setup_bundle_cache() {
    local VERSION="$1"
    local REDMINE_DIR="$2"

    local CACHE_DIR="${PLUGIN_ROOT}/.bundle-cache/${VERSION}"
    mkdir -p "$CACHE_DIR"

    # Create symlink if it doesn't exist
    if [ ! -L "${REDMINE_DIR}/.bundle-cache" ]; then
        ln -sf "$CACHE_DIR" "${REDMINE_DIR}/.bundle-cache" 2>/dev/null || true
    fi

    echo "$CACHE_DIR"
}

# Run tests for specific Redmine version
run_tests() {
    local VERSION="$1"
    local REDMINE_DIR

    REDMINE_DIR="$(detect_redmine_dir "$VERSION")"

    if [ ! -d "$REDMINE_DIR" ]; then
        error "Redmine directory not found: $REDMINE_DIR"
        exit 1
    fi

    info "Running tests against Redmine ${VERSION} at: $REDMINE_DIR"

    # Setup bundle cache
    local BUNDLE_CACHE_DIR
    BUNDLE_CACHE_DIR="$(setup_bundle_cache "$VERSION" "$REDMINE_DIR")"

    # Create database config
    local DB_CONFIG="${REDMINE_DIR}/config/database.yml"
    cat > "$DB_CONFIG" << EOF
test:
  adapter: sqlite3
  database: db/redmine_test.sqlite3
  pool: 5
  timeout: 5000
EOF

    # Setup environment
    export BUNDLE_PATH="$BUNDLE_CACHE_DIR"
    export BUNDLE_APP_CONFIG="${BUNDLE_CACHE_DIR}/.bundle"
    export RUBYLIB="${PLUGIN_ROOT}/test"
    export RAILS_ENV="test"

    cd "$REDMINE_DIR"

    setup_bundler_cmd "$VERSION"

    # Install dependencies if needed
    if ! "${BUNDLE_CMD[@]}" check >/dev/null 2>&1; then
        info "Installing bundle dependencies..."
        "${BUNDLE_CMD[@]}" install --jobs 4 --retry 3
    fi

    "${BUNDLE_CMD[@]}" exec rake db:environment:set RAILS_ENV=test || true

    # Setup database based on Rails version
    if [ "$VERSION" = "6.1.0" ]; then
        info "Setting up Rails 8 database (schema load)..."

        # Drop existing database
        "${BUNDLE_CMD[@]}" exec rake db:drop RAILS_ENV=test || true

        # Create and load schema
        "${BUNDLE_CMD[@]}" exec rake db:create db:schema:load RAILS_ENV=test

        # Handle Rails 8 schema_migrations issue
        sqlite3 db/redmine_test.sqlite3 "CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR(255) NOT NULL UNIQUE PRIMARY KEY);" 2>/dev/null || true
        sqlite3 db/redmine_test.sqlite3 "CREATE UNIQUE INDEX IF NOT EXISTS unique_schema_migrations ON schema_migrations (version);" 2>/dev/null || true
        sqlite3 db/redmine_test.sqlite3 "DROP TABLE IF EXISTS webhook_endpoints;" 2>/dev/null || true
        sqlite3 db/redmine_test.sqlite3 "DROP TABLE IF EXISTS webhook_deliveries;" 2>/dev/null || true
    else
        info "Setting up Rails 7 database (migrate)..."
        "${BUNDLE_CMD[@]}" exec rake db:drop db:create db:migrate RAILS_ENV=test || true
    fi

    # Run plugin migrations
    info "Running plugin migrations..."
    "${BUNDLE_CMD[@]}" exec rake redmine:plugins:migrate RAILS_ENV=test

    # Run tests
    info "Running plugin tests..."
    local LOG_FILE="${PLUGIN_ROOT}/logs/run-test-${VERSION}.log"
    local TESTOPTS_ENV=()
    local TESTOPTS_VALUE

    TESTOPTS_VALUE="$(testopts_for_version "$VERSION")"
    if [ -n "$TESTOPTS_VALUE" ]; then
        TESTOPTS_ENV=(TESTOPTS="$TESTOPTS_VALUE")
    fi

    mkdir -p "$(dirname "$LOG_FILE")"

    if [ -n "${TESTFILE:-}" ]; then
        local TEST_PATH
        TEST_PATH="$(testfile_path)"

        info "Running single test file: ${TEST_PATH}"
        if [ ! -f "${REDMINE_DIR}/${TEST_PATH}" ]; then
            error "Test file not found: ${REDMINE_DIR}/${TEST_PATH}"
            return 1
        fi

        if "${TESTOPTS_ENV[@]}" "${BUNDLE_CMD[@]}" exec ruby -Ilib:test "${TEST_PATH}" -v 2>&1 | tee "$LOG_FILE"; then
            success "Tests passed for Redmine ${VERSION}"
            return 0
        else
            error "Tests failed for Redmine ${VERSION}"
            info "Check log file: $LOG_FILE"
            return 1
        fi
    fi

    if "${TESTOPTS_ENV[@]}" "${BUNDLE_CMD[@]}" exec ruby -I"${PLUGIN_ROOT}/test" -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test 2>&1 | tee "$LOG_FILE"; then
        success "Tests passed for Redmine ${VERSION}"
        return 0
    else
        error "Tests failed for Redmine ${VERSION}"
        info "Check log file: $LOG_FILE"
        return 1
    fi
}

# Run tests using podman helper script for a specific version
run_tests_podman() {
    local VERSION="$1"
    local PODMAN_SCRIPT="${SCRIPT_DIR}/test-${VERSION}.sh"
    local REDMINE_DIR

    if [ -n "${TESTFILE:-}" ]; then
        run_tests_podman_single "$VERSION"
        return
    fi

    if [ ! -f "$PODMAN_SCRIPT" ]; then
        error "Podman test script not found: $PODMAN_SCRIPT"
        exit 1
    fi

    REDMINE_DIR="$(detect_redmine_dir "$VERSION")"
    if [ ! -d "$REDMINE_DIR" ]; then
        error "Redmine directory not found: $REDMINE_DIR"
        exit 1
    fi

    local TESTOPTS_VALUE

    info "Running podman test script for Redmine ${VERSION}: ${PODMAN_SCRIPT}"
    info "Using Redmine directory: ${REDMINE_DIR}"

    TESTOPTS_VALUE="$(testopts_for_version "$VERSION")"
    if [ -n "$TESTOPTS_VALUE" ]; then
        TESTOPTS="$TESTOPTS_VALUE" REDMINE_DIR="$REDMINE_DIR" bash "$PODMAN_SCRIPT"
    else
        REDMINE_DIR="$REDMINE_DIR" bash "$PODMAN_SCRIPT"
    fi
}

run_tests_podman_single() {
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
    if [ ! -d "$REDMINE_DIR" ]; then
        error "Redmine directory not found: $REDMINE_DIR"
        exit 1
    fi

    TEST_PATH="$(testfile_path)"
    if [ ! -f "${PLUGIN_ROOT}/test/unit/${TESTFILE%.rb}.rb" ]; then
        error "Test file not found: ${PLUGIN_ROOT}/test/unit/${TESTFILE%.rb}.rb"
        exit 1
    fi

    BUNDLE_DIR="${PLUGIN_ROOT}/.bundle-cache/${VERSION}"
    LOG_DIR="${PLUGIN_ROOT}/logs"
    LOG_FILE="${LOG_DIR}/run-test-${VERSION}.log"
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

    info "Running podman single test for Redmine ${VERSION}: ${TEST_PATH}"
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
      2>&1 | tee >(sed -E "s/${ESC}\\[[0-9;]*[[:alpha:]]//g" > "$LOG_FILE")
}

# Resolve list of versions to test
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

# Main execution
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
        info "Starting unified test runner (podman) for Redmine: ${VERSIONS}"
    else
        info "Starting unified test runner (host) for Redmine: ${VERSIONS}"
    fi

    for V in $VERSIONS; do
        if use_podman; then
            run_tests_podman "$V"
        else
            run_tests "$V"
        fi
    done

    success "All tests completed successfully"
    exit 0
}

# Run main function
main "$@"
