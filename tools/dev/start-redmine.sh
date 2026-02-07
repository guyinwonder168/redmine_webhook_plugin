#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Redmine Web Server Launcher
# =============================================================================
# Purpose: Run Redmine containers with browser access for manual testing
#
# Supports:
#   - Redmine 5.1.0   (Port 3000) - Ruby 3.2.2, Rails 6.1.7.6
#   - Redmine 5.1.10  (Port 3001) - Ruby 3.2.2, Rails 6.1.7.8
#   - Redmine 6.1.0   (Port 3002) - Ruby 3.3.4, Rails 8.0.4
#   - Redmine 7.0.0-dev (Port 3003) - Ruby 3.3.4, Rails 8.0 (trunk)
#
# Features:
#   - Bundler cache configuration (BUNDLE_APP_CONFIG)
#   - Clean SQLite database on each start
#   - Standard Redmine bootstrap (secret, db:migrate, default data)
#   - Plugin migrations (after core bootstrap)
#   - Dummy project data seeding (with --seed flag)
#   - Gemfile.local with minitest 5.x pin
#   - Background containers with logs
#
# Usage:
#   ./start-redmine.sh              # Show help
#   ./start-redmine.sh 5.1.0      # Start Redmine 5.1.0 only
#   ./start-redmine.sh 5.1.0 --seed # Start with dummy projects
#   ./start-redmine.sh 5.1.10     # Start Redmine 5.1.10 only
#   ./start-redmine.sh 6.1.0      # Start Redmine 6.1.0 only
#   ./start-redmine.sh all         # Start all versions
#   ./start-redmine.sh all --seed # Start all with dummy projects
#   ./stop-redmine.sh             # Stop all Redmine containers
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_DIR="${ROOT_DIR:-}"

if [ -n "${ROOT_DIR}" ]; then
    REDMINE_ROOT="${REDMINE_ROOT:-${ROOT_DIR}}"
    BUNDLE_ROOT="${BUNDLE_ROOT:-${ROOT_DIR}}"
    PLUGIN_DIR="${PLUGIN_DIR:-${ROOT_DIR}/redmine_webhook_plugin}"
else
    REDMINE_ROOT="${REDMINE_ROOT:-${PLUGIN_ROOT}/.redmine-test}"
    BUNDLE_ROOT="${BUNDLE_ROOT:-${PLUGIN_ROOT}}"
    PLUGIN_DIR="${PLUGIN_DIR:-${PLUGIN_ROOT}}"
fi

# Color codes for output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# Container configuration (image|port|redmine_dir|bundle_dir|rails_version)
declare -A REDMINE_CONFIG=(
    ["5.1.0"]="redmine-dev:5.1.0|3000|redmine-5.1.0|.bundle-cache/5.1.0|6.1"
    ["5.1.10"]="redmine-dev:5.1.10|3001|redmine-5.1.10|.bundle-cache/5.1.10|6.1"
    ["6.1.0"]="redmine-dev:6.1.0|3002|redmine-6.1.0|.bundle-cache/6.1.0|8.0"
    ["7.0.0-dev"]="redmine-dev:7.0.0-dev|3003|redmine-7.0.0-dev|.bundle-cache/7.0.0-dev|8.0"
)

# Print colored message
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Show usage
show_usage() {
    cat << EOF
${GREEN}Redmine Web Server Launcher${NC}

${BLUE}Usage:${NC}
  $0 [VERSION]              Start specific Redmine version
  $0 [VERSION] --seed      Start with dummy project data
  $0 all                    Start all Redmine versions
  $0 all --seed             Start all with dummy project data
  $0 stop                   Stop all Redmine containers
  $0 logs [VERSION]         Show logs for specific version
  $0 status                 Show running containers status

${BLUE}Supported Versions:${NC}
  5.1.0      (Port 3000) - Ruby 3.2.2, Rails 6.1
  5.1.10     (Port 3001) - Ruby 3.2.2, Rails 6.1
  6.1.0      (Port 3002) - Ruby 3.3.4, Rails 8.0
  7.0.0-dev  (Port 3003) - Ruby 3.3.4, Rails 8.0 (trunk)

${BLUE}Examples:${NC}
  $0 5.1.0                Start Redmine 5.1.0
  $0 5.1.0 --seed         Start Redmine 5.1.0 with dummy projects
  $0 5.1.10               Start Redmine 5.1.10
  $0 6.1.0                Start Redmine 6.1.0
  $0 6.1.0 --seed         Start Redmine 6.1.0 with dummy projects
  $0 7.0.0-dev            Start Redmine 7.0.0-dev
  $0 7.0.0-dev --seed     Start Redmine 7.0.0-dev with dummy projects
  $0 all                  Start all versions
  $0 all --seed           Start all with dummy projects
  $0 logs 5.1.0          Show logs for 5.1.0

${BLUE}Default Credentials:${NC}
  Username: admin
  Password: admin (5.1.x, 5.1.10)
  Password: Admin1234! (6.1.0, 7.0.0-dev)

${BLUE}Dummy Projects (--seed flag):${NC}
  When using --seed, 5 dummy projects are created:
  • Marketing Website (marketing-web)
  • Mobile App (mobile-app)
  • API Services (api-services)
  • Internal Tools (internal-tools)
  • Documentation (docs)

  These projects are available for selection in webhook endpoints.

${BLUE}To stop all containers:${NC}
  $0 stop

${BLUE}To check running containers:${NC}
  $0 status

EOF
}

# Check if container is already running
is_container_running() {
    local container_name=$1
    podman ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "^${container_name}$"
}

# Stop all Redmine containers
stop_all_containers() {
    print_msg "${YELLOW}" "Stopping all Redmine containers..."

    for version in "${!REDMINE_CONFIG[@]}"; do
        IFS='|' read -r image port redmine_dir bundle_dir <<< "${REDMINE_CONFIG[$version]}"
        local container_name="redmine-${version//./-}"

        if is_container_running "${container_name}"; then
            print_msg "${YELLOW}" "  Stopping ${version}..."
            podman stop "${container_name}" >/dev/null 2>&1 || true
        fi
    done

    # Also try to remove stopped containers
    print_msg "${YELLOW}" "Cleaning up stopped containers..."
    for version in "${!REDMINE_CONFIG[@]}"; do
        IFS='|' read -r image port redmine_dir bundle_dir <<< "${REDMINE_CONFIG[$version]}"
        local container_name="redmine-${version//./-}"
        podman rm -f "${container_name}" >/dev/null 2>&1 || true
    done

    print_msg "${GREEN}" "✓ All containers stopped"
}

# Show status of all Redmine containers
show_status() {
    print_msg "${BLUE}" "Redmine Container Status"
    echo ""

    local running=0
    local total=${#REDMINE_CONFIG[@]}
    for version in "${!REDMINE_CONFIG[@]}"; do
        IFS='|' read -r image port redmine_dir bundle_dir <<< "${REDMINE_CONFIG[$version]}"
        local container_name="redmine-${version//./-}"
        local status_icon="🔴"
        local status_text="Stopped"

        if is_container_running "${container_name}"; then
            status_icon="🟢"
            status_text="Running"
            running=$((running + 1))
        fi

        echo -e "  ${status_icon} Redmine ${version} - ${status_text} - http://localhost:${port}"
    done

    echo ""
    print_msg "${GREEN}" "Total running: ${running}/${total}"
    echo ""

    if [ $running -gt 0 ]; then
        print_msg "${BLUE}" "To view logs:"
        echo "  $0 logs [VERSION]"
        echo ""
    fi
}

# Show logs for specific container
show_logs() {
    local version=$1

    if [ -z "${REDMINE_CONFIG[$version]+undefined}" ]; then
        print_msg "${RED}" "Error: Invalid version '${version}'"
        echo ""
        show_usage
        exit 1
    fi

    IFS='|' read -r image port redmine_dir bundle_dir <<< "${REDMINE_CONFIG[$version]}"
    local container_name="redmine-${version//./-}"

    if ! is_container_running "${container_name}"; then
        print_msg "${RED}" "Error: Container for Redmine ${version} is not running"
        exit 1
    fi

    print_msg "${BLUE}" "Showing logs for Redmine ${version}..."
    podman logs -f "${container_name}"
}

# Start a specific Redmine version
start_redmine_version() {
    local version=$1
    local seed_data="${2:-}"

    if [ -z "${REDMINE_CONFIG[$version]+undefined}" ]; then
        print_msg "${RED}" "Error: Invalid version '${version}'"
        echo ""
        show_usage
        exit 1
    fi

    IFS='|' read -r image port redmine_dir bundle_dir rails_version <<< "${REDMINE_CONFIG[$version]}"
    local full_redmine_dir="${REDMINE_ROOT}/${redmine_dir}"
    local full_bundle_dir="${BUNDLE_ROOT}/${bundle_dir}"
    local container_name="redmine-${version//./-}"
    local bundler_version=""

    case "${version}" in
        5.1.0|5.1.10)
            bundler_version="2.4.10"
            ;;
        6.1.0|7.0.0-dev)
            bundler_version="2.5.11"
            ;;
    esac

    # Check if container is already running
    if is_container_running "${container_name}"; then
        print_msg "${YELLOW}" "Warning: Container for Redmine ${version} is already running"
        print_msg "${YELLOW}" "  Access: http://localhost:${port}"
        print_msg "${YELLOW}" "  Stop it first with: $0 stop"
        exit 1
    fi

    # Ensure Gemfile.local exists for 5.1.0 (minitest 5.x pin)
    if [ "${version}" = "5.1.0" ]; then
        local gemfile_local="${full_redmine_dir}/Gemfile.local"
        if [ ! -f "${gemfile_local}" ]; then
            print_msg "${YELLOW}" "Creating Gemfile.local for minitest 5.x pin..."
            echo "gem 'minitest', '~> 5.0'" > "${gemfile_local}"
        fi
    fi

    # Create bundle cache directory
    mkdir -p "${full_bundle_dir}"

    # Determine seeding strategy
    local seed_cmd=""
    local seed_note=""
    
    if [ "${seed_data}" = "--seed" ]; then
        print_msg "${YELLOW}" "📊 Seeding with dummy project data..."
        seed_note=" (with dummy projects)"
    fi

    print_msg "${GREEN}" "================================================================"
    print_msg "${GREEN}" "🚀 Starting Redmine ${version}${seed_note}"
    print_msg "${GREEN}" "================================================================"
    echo ""
    echo -e "  ${BLUE}Redmine:${NC}  ${full_redmine_dir}"
    echo -e "  ${BLUE}Plugin:${NC}   ${PLUGIN_DIR}"
    echo -e "  ${BLUE}Bundle:${NC}   ${full_bundle_dir}"
    echo -e "  ${BLUE}Image:${NC}    ${image}"
    echo -e "  ${BLUE}Port:${NC}     ${port}"
    echo ""
    print_msg "${GREEN}" "================================================================"
    echo ""

    # Remove old container if it exists (but not running)
    podman rm -f "${container_name}" >/dev/null 2>&1 || true

    local bootstrap_script
    bootstrap_script=$(cat <<'SCRIPT'
    set -euo pipefail
    cd /redmine
    export RAILS_ENV=development

    BUNDLE_CMD=(bundle)
    if [ -n "${BUNDLER_VERSION:-}" ]; then
      if ! gem list -i bundler -v "${BUNDLER_VERSION}" >/dev/null 2>&1; then
        echo "📦 Installing bundler ${BUNDLER_VERSION}..."
        gem install bundler -v "${BUNDLER_VERSION}"
      fi
      BUNDLE_CMD=(bundle "_${BUNDLER_VERSION}_")
    fi

    CONTAINER_PORT=3000

    echo '📦 Checking gems...'
    if ! "${BUNDLE_CMD[@]}" check 2>/dev/null; then
      echo '📦 Installing gems (this may take a minute)...'
      "${BUNDLE_CMD[@]}" install --jobs 4 --retry 3
    fi

    echo ''
    echo '✓ Gems installed'
    echo ''
    echo '🗄️  Setting up database...'
    printf "development:\n  adapter: sqlite3\n  database: db/redmine.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml
    rm -f db/redmine.sqlite3

    echo '🔐 Generating secret token...'
    "${BUNDLE_CMD[@]}" exec rake generate_secret_token

    echo '  Running database migrations (includes admin user creation)...'
    "${BUNDLE_CMD[@]}" exec rake db:migrate

    if ! "${BUNDLE_CMD[@]}" exec rails runner 'exit(User.where(login: "admin").exists? ? 0 : 1)'; then
      echo '⚠ Admin user not created by db:migrate (will create after)'
    fi

    echo ''
    echo '✓ Database created'
    echo ''
    if [ "${REDMINE_VERSION}" = "6.1.0" ] || [ "${REDMINE_VERSION}" = "7.0.0-dev" ]; then
      echo '🔑 Ensuring admin user exists (dev default password)...'
      "${BUNDLE_CMD[@]}" exec rails runner 'u = User.find_or_initialize_by(login: "admin"); u.password = "Admin1234!"; u.password_confirmation = "Admin1234!"; u.firstname = "Redmine" if u.firstname.to_s.strip.empty?; u.lastname = "Admin" if u.lastname.to_s.strip.empty?; u.mail = "admin@example.net" if u.mail.to_s.strip.empty?; u.admin = true; u.status = User::STATUS_ACTIVE; u.save!'
      echo ''
    fi
    echo ''
    echo '🔧 Loading default configuration data...'
    REDMINE_LANG=en "${BUNDLE_CMD[@]}" exec rake redmine:load_default_data

    echo ''
    echo '🔌 Running plugin migrations...'
    "${BUNDLE_CMD[@]}" exec rake redmine:plugins:migrate

    if [ "${SEED_DATA}" = "--seed" ]; then
      echo ''
      echo '  📊 Seeding dummy projects...'
      "${BUNDLE_CMD[@]}" exec rails runner /redmine/plugins/redmine_webhook_plugin/db/seeds.rb
    fi

    echo ''
    echo '  🌐 Starting Rails server...'
    echo ''
    echo '========================================'
    echo '  ✓ Redmine is ready!'
    echo '========================================'
    echo ''
    echo "  Access: http://localhost:${REDMINE_HOST_PORT}"
    if [ "${REDMINE_VERSION}" = "6.1.0" ] || [ "${REDMINE_VERSION}" = "7.0.0-dev" ]; then
      echo '  Log in: admin / Admin1234!'
    else
      echo '  Log in: admin / admin'
    fi
    echo ''
    echo '  To stop: ./start-redmine.sh stop'
    echo "  To view logs: ./start-redmine.sh logs ${REDMINE_VERSION}"
    echo '  ======================================='
    echo ''
    "${BUNDLE_CMD[@]}" exec rails server -b 0.0.0.0 -p "${CONTAINER_PORT}" -e development
SCRIPT
)

    # Start container in background
    podman run -d --name "${container_name}" \
        -v "${full_redmine_dir}:/redmine:rw" \
        -v "${PLUGIN_DIR}:/redmine/plugins/redmine_webhook_plugin:rw" \
        -v "${full_bundle_dir}:/bundle:rw" \
        -e BUNDLE_PATH=/bundle \
        -e BUNDLE_APP_CONFIG=/bundle/.bundle \
        -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
        -e REDMINE_HOST_PORT="${port}" \
        -e SEED_DATA="${seed_data}" \
        -e REDMINE_VERSION="${version}" \
        -e BUNDLER_VERSION="${bundler_version}" \
        -p "${port}:3000" \
        "${image}" \
        bash -lc "$bootstrap_script"

    # Wait a moment for container to initialize
    sleep 3

    # Check if container is running
    if is_container_running "${container_name}"; then
        echo ""
        print_msg "${GREEN}" "✓ Redmine ${version} is starting..."
        echo ""
        print_msg "${BLUE}" "Access URL: http://localhost:${port}"
        print_msg "${BLUE}" "Username:   admin"
        if [ "${version}" = "6.1.0" ] || [ "${version}" = "7.0.0-dev" ]; then
            print_msg "${BLUE}" "Password:   Admin1234!"
        else
            print_msg "${BLUE}" "Password:   admin"
        fi
        echo ""
        print_msg "${YELLOW}" "To view logs: $0 logs ${version}"
        print_msg "${YELLOW}" "To stop: $0 stop"
        echo ""
    else
        print_msg "${RED}" "✗ Failed to start Redamine ${version}"
        echo ""
        print_msg "${YELLOW}" "Check logs for errors:"
        print_msg "${YELLOW}" "  podman logs ${container_name}"
        echo ""
        exit 1
    fi
}

# Start all Redmine versions in parallel
start_all_versions() {
    local seed_flag="${2:-}"
    print_msg "${GREEN}" "Starting all Redmine versions..."

    for version in 5.1.0 5.1.10 6.1.0 7.0.0-dev; do
        start_redmine_version "${version}" "${seed_flag}"
        echo ""
    done

    print_msg "${GREEN}" "================================================================"
    print_msg "${GREEN}" "✓ All Redmine versions are running!"
    print_msg "${GREEN}" "================================================================"
    echo ""
    echo "Access URLs:"
    echo "  • Redmine 5.1.0:    http://localhost:3000"
    echo "  • Redmine 5.1.10:   http://localhost:3001"
    echo "  • Redmine 6.1.0:    http://localhost:3002"
    echo "  • Redmine 7.0.0-dev: http://localhost:3003"
    echo ""
    echo "Credentials:"
    echo "  - 5.1.x: admin / admin"
    echo "  - 6.1.0, 7.0.0-dev: admin / Admin1234!"
    echo ""
    print_msg "${YELLOW}" "To stop all: $0 stop"
    print_msg "${YELLOW}" "To view status: $0 status"
    echo ""
}

# Main entry point
main() {
    local command=${1:-}

    case "${command}" in
        ""|"-h"|"--help"|"help")
            show_usage
            ;;
        "5.1.0"|"5.1.10"|"6.1.0"|"7.0.0-dev")
            local seed_flag="${2:-}"
            start_redmine_version "${command}" "${seed_flag}"
            ;;
        "all")
            local seed_flag="${2:-}"
            start_all_versions all "${seed_flag}"
            ;;
        "stop")
            stop_all_containers
            ;;
        "status")
            show_status
            ;;
        "logs")
            if [ -z "${2:-}" ]; then
                print_msg "${RED}" "Error: Version required for logs command"
                echo ""
                print_msg "${YELLOW}" "Usage: $0 logs [VERSION]"
                echo "  $0 logs 5.1.0"
                echo "  $0 logs 5.1.10"
                echo "  $0 logs 6.1.0"
                echo "  $0 logs 7.0.0-dev"
                exit 1
            fi
            show_logs "$2"
            ;;
        *)
            print_msg "${RED}" "Error: Unknown command '${command}'"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
