#!/bin/bash

#############################################
# Redmine Webhook Plugin Installer
# Version: 1.0.0
# Supported Redmine: 5.1.0, 5.1.10, 6.1.0, 7.0.0+
#############################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REDMINE_DIR=""
PLUGIN_NAME="redmine_webhook_plugin"
VERSION="1.0.0-RC"
INSTALL_SOURCE=""
BACKUP_DIR=""
SKIP_BACKUP=false
SKIP_MIGRATIONS=false
RESTART_SERVER=false
WEB_USER=""
RAILS_ENV="production"

# Display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install Redmine Webhook Plugin to a Redmine installation.

OPTIONS:
    -d, --redmine-dir PATH     Path to Redmine installation (required)
    -s, --source PATH|URL     Plugin source: local path or GitHub URL
    -b, --backup DIR          Backup directory (default: ./backups/timestamp)
    -B, --skip-backup        Skip backup before installation
    -M, --skip-migrations     Skip database migrations
    -R, --restart-server      Restart web server after installation
    -u, --web-user USER       Web server user (e.g., www-data, nginx)
    -e, --rails-env ENV       Rails environment (default: production)
    -v, --version VERSION      Plugin version to install
    -h, --help               Show this help message

EXAMPLES:
    # Install to /var/www/redmine
    $0 -d /var/www/redmine

    # Install from local source with backup
    $0 -d /var/www/redmine -s /path/to/plugin -b /backup

    # Install from GitHub release
    $0 -d /var/www/redmine -s https://github.com/guyinwonder168/redmine_webhook_plugin/archive/refs/tags/v1.0.0-RC.tar.gz

    # Full installation with restart
    $0 -d /var/www/redmine -R -u www-data

EOF
    exit 1
}

# Print colored message
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or specified user
check_permissions() {
    if [ -n "$WEB_USER" ] && [ "$(whoami)" != "root" ] && [ "$(whoami)" != "$WEB_USER" ]; then
        log_error "This script must be run as root or as $WEB_USER"
        exit 1
    fi
}

# Validate Redmine installation
validate_redmine() {
    if [ -z "$REDMINE_DIR" ]; then
        log_error "Redmine directory not specified. Use -d or --redmine-dir"
        usage
    fi

    if [ ! -d "$REDMINE_DIR" ]; then
        log_error "Redmine directory does not exist: $REDMINE_DIR"
        exit 1
    fi

    if [ ! -f "$REDMINE_DIR/Rakefile" ]; then
        log_error "Invalid Redmine installation: $REDMINE_DIR (no Rakefile found)"
        exit 1
    fi

    log_success "Redmine installation validated: $REDMINE_DIR"
}

# Check Redmine version
check_redmine_version() {
    log_info "Checking Redmine version..."
    local version_file="$REDMINE_DIR/lib/redmine/version.rb"
    if [ -f "$version_file" ]; then
        local redmine_version=$(grep -oP 'MAJOR\s*=\s*\K\d+' "$version_file").$(grep -oP 'MINOR\s*=\s*\K\d+' "$version_file").$(grep -oP 'TINY\s*=\s*\K\d+' "$version_file")
        log_info "Redmine version detected: $redmine_version"

        # Check version compatibility
        local major_version=$(echo "$redmine_version" | cut -d. -f1)
        local minor_version=$(echo "$redmine_version" | cut -d. -f2)

        if [ "$major_version" -lt 5 ]; then
            log_error "Redmine version $redmine_version is not supported (minimum: 5.1.0)"
            exit 1
        elif [ "$major_version" -eq 5 ] && [ "$minor_version" -lt 1 ]; then
            log_error "Redmine version $redmine_version is not supported (minimum: 5.1.0)"
            exit 1
        fi

        log_success "Redmine version $redmine_version is compatible"
    else
        log_warning "Could not detect Redmine version, proceeding anyway"
    fi
}

# Backup existing plugin
backup_plugin() {
    if [ "$SKIP_BACKUP" = true ]; then
        log_warning "Skipping backup"
        return
    fi

    local plugin_path="$REDMINE_DIR/plugins/$PLUGIN_NAME"
    if [ -d "$plugin_path" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        BACKUP_DIR="${BACKUP_DIR:-./backups}/$timestamp"

        log_info "Creating backup at $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        cp -r "$plugin_path" "$BACKUP_DIR/"

        log_success "Backup created: $BACKUP_DIR"
    else
        log_info "No existing plugin to backup (fresh installation)"
    fi
}

# Download plugin from URL
download_plugin() {
    if [[ "$INSTALL_SOURCE" =~ ^https?:// ]]; then
        log_info "Downloading plugin from $INSTALL_SOURCE..."
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"

        if command -v wget >/dev/null 2>&1; then
            wget -q --show-progress "$INSTALL_SOURCE" -o plugin.tar.gz
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o plugin.tar.gz "$INSTALL_SOURCE"
        else
            log_error "Neither wget nor curl found. Please install one."
            exit 1
        fi

        log_info "Extracting plugin..."
        tar -xzf plugin.tar.gz

        # Find the extracted directory
        local extracted_dir=$(find . -maxdepth 1 -type d -name "${PLUGIN_NAME}*" | head -1)
        if [ -z "$extracted_dir" ]; then
            log_error "Could not find plugin directory in archive"
            exit 1
        fi

        INSTALL_SOURCE="$temp_dir/$extracted_dir"
        log_success "Plugin downloaded and extracted"
    fi
}

# Install plugin
install_plugin() {
    log_info "Installing plugin $PLUGIN_NAME v$VERSION..."

    local plugin_path="$REDMINE_DIR/plugins/$PLUGIN_NAME"

    # Remove existing plugin if present
    if [ -d "$plugin_path" ]; then
        log_info "Removing existing plugin installation..."
        rm -rf "$plugin_path"
    fi

    # Copy plugin to Redmine
    if [ -d "$INSTALL_SOURCE" ]; then
        log_info "Copying plugin from $INSTALL_SOURCE..."
        cp -r "$INSTALL_SOURCE" "$plugin_path"
    else
        log_error "Invalid source: $INSTALL_SOURCE (directory not found)"
        exit 1
    fi

    # Set permissions if web user specified
    if [ -n "$WEB_USER" ]; then
        log_info "Setting permissions for $WEB_USER..."
        chown -R "$WEB_USER:$WEB_USER" "$plugin_path"
    fi

    log_success "Plugin installed to $plugin_path"
}

# Run database migrations
run_migrations() {
    if [ "$SKIP_MIGRATIONS" = true ]; then
        log_warning "Skipping migrations"
        return
    fi

    log_info "Running database migrations..."
    cd "$REDMINE_DIR"

    # Run plugin migrations
    RAILS_ENV=$RAILS_ENV bundle exec rake redmine:plugins:migrate NAME=$PLUGIN_NAME

    log_success "Migrations completed"
}

# Install bundle dependencies
install_dependencies() {
    log_info "Installing bundle dependencies..."
    cd "$REDMINE_DIR"

    RAILS_ENV=$RAILS_ENV bundle install

    log_success "Dependencies installed"
}

# Restart web server
restart_web_server() {
    if [ "$RESTART_SERVER" = false ]; then
        log_info "Web server restart skipped"
        return
    fi

    log_info "Restarting web server..."

    # Try common web servers
    if systemctl is-active --quiet apache2 2>/dev/null; then
        systemctl reload apache2
        log_success "Apache2 reloaded"
    elif systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl restart nginx
        log_success "Nginx restarted"
    elif systemctl is-active --quiet puma 2>/dev/null; then
        systemctl restart puma
        log_success "Puma restarted"
    else
        log_warning "Could not detect web server. Please restart manually."
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    local init_file="$REDMINE_DIR/plugins/$PLUGIN_NAME/init.rb"
    if [ ! -f "$init_file" ]; then
        log_error "Installation failed: init.rb not found"
        exit 1
    fi

    # Check plugin is registered
    cd "$REDMINE_DIR"
    local plugin_check=$(RAILS_ENV=$RAILS_ENV bundle exec rake redmine:plugins:check 2>&1 || true)
    if echo "$plugin_check" | grep -q "$PLUGIN_NAME"; then
        log_success "Plugin is properly registered"
    else
        log_warning "Could not verify plugin registration. Check Redmine logs."
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Plugin: $PLUGIN_NAME v$VERSION"
    echo "Redmine: $REDMINE_DIR"
    echo "Environment: $RAILS_ENV"
    echo "Backup: ${BACKUP_DIR:-none}"
    echo ""
    echo "Next steps:"
    echo "1. Restart your web server (if not done automatically)"
    echo "2. Check Redmine Administration > Plugins for the plugin"
    echo "3. Configure webhook endpoints in Administration > Webhook Endpoints"
    echo "4. Monitor webhook deliveries in Administration > Webhook Deliveries"
    echo ""
    echo "Documentation: https://github.com/guyinwonder168/redmine_webhook_plugin/releases/tag/v1.0.0-RC"
    echo ""
}

# Main installation flow
main() {
    echo ""
    echo -e "${BLUE}Redmine Webhook Plugin Installer v1.0.0${NC}"
    echo ""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--redmine-dir)
                REDMINE_DIR="$2"
                shift 2
                ;;
            -s|--source)
                INSTALL_SOURCE="$2"
                shift 2
                ;;
            -b|--backup)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -B|--skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            -M|--skip-migrations)
                SKIP_MIGRATIONS=true
                shift
                ;;
            -R|--restart-server)
                RESTART_SERVER=true
                shift
                ;;
            -u|--web-user)
                WEB_USER="$2"
                shift 2
                ;;
            -e|--rails-env)
                RAILS_ENV="$2"
                shift 2
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Use current directory if source not specified
    if [ -z "$INSTALL_SOURCE" ]; then
        INSTALL_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        log_info "No source specified, using current directory: $INSTALL_SOURCE"
    fi

    # Execute installation steps
    check_permissions
    validate_redmine
    check_redmine_version
    backup_plugin
    download_plugin
    install_plugin
    install_dependencies
    run_migrations
    restart_web_server
    verify_installation
    print_summary
}

# Run main function
main "$@"
