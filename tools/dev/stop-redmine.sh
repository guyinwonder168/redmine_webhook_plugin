#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Redmine Container Stopper
# =============================================================================
# Convenience script to stop all Redmine containers and remove images
#
# Usage: ./stop-redmine.sh [OPTIONS]
# Options:
#   --images    Also remove container images (rebuild required next start)
#   --clean-all  Stop containers, remove containers and images
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Parse options
remove_images=false
remove_all=false

for arg in "$@"; do
    case "$arg" in
        --images)
            remove_images=true
            ;;
        --clean-all)
            remove_all=true
            remove_images=true
            ;;
        --help|-h)
            cat << EOF
${GREEN}Redmine Container Stopper${NC}

${BLUE}Usage:${NC}
  $0                  Stop containers only
  $0 --images         Stop containers and remove images
  $0 --clean-all      Stop containers, remove containers and images

${BLUE}Examples:${NC}
  $0                  # Stop all Redmine containers
  $0 --images         # Stop and remove images (rebuild on next start)
  $0 --clean-all      # Complete cleanup (containers + images)

EOF
            exit 0
            ;;
    esac
done

print_msg "${YELLOW}" "Stopping all Redmine containers..."

# Array of container names and corresponding images
declare -A containers_and_images=(
    ["redmine-5-1-0"]="redmine-dev:5.1.0"
    ["redmine-5-1-10"]="redmine-dev:5.1.10"
    ["redmine-6-1-0"]="redmine-dev:6.1.0"
    ["redmine-7-0-0-dev"]="redmine-dev:7.0.0-dev"
)

stopped=0
removed=0

for container in "${!containers_and_images[@]}"; do
    if podman ps --filter "name=${container}" --format "{{.Names}}" | grep -q "^${container}$"; then
        print_msg "${YELLOW}" "  Stopping ${container}..."
        podman stop "${container}" >/dev/null 2>&1 && stopped=$((stopped + 1)) || true
    fi
done

# Also try to remove stopped containers
print_msg "${YELLOW}" "Cleaning up stopped containers..."
for container in "${!containers_and_images[@]}"; do
    podman rm -f "${container}" >/dev/null 2>&1 && removed=$((removed + 1)) || true
done

if [ $stopped -eq 0 ]; then
    print_msg "${YELLOW}" "No running containers to stop"
else
    print_msg "${GREEN}" "✓ Stopped ${stopped} container(s)"
fi

if [ $removed -gt 0 ]; then
    print_msg "${GREEN}" "✓ Removed ${removed} container(s)"
fi

# Remove images if requested
if [ "$remove_images" = true ]; then
    print_msg "${YELLOW}" "Removing container images..."
    images_removed=0

    for container in "${!containers_and_images[@]}"; do
        image="${containers_and_images[$container]}"
        if podman images "${image}" --format "{{.Repository}}:{{.Tag}}" | grep -q "${image}"; then
            print_msg "${YELLOW}" "  Removing image: ${image}..."
            podman rmi "${image}" >/dev/null 2>&1 && images_removed=$((images_removed + 1)) || true
        fi
    done

    if [ $images_removed -gt 0 ]; then
        print_msg "${GREEN}" "✓ Removed ${images_removed} image(s)"
    else
        print_msg "${YELLOW}" "No images found to remove"
    fi
fi

print_msg "${GREEN}" "✓ Cleanup complete"
