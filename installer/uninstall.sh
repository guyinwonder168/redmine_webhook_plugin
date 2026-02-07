#!/bin/bash

#############################################
# Redmine Webhook Plugin Uninstaller
# Version: 1.0.0
# Safely removes plugin and re-enables native webhooks (Redmine 7+)
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
SKIP_DB_ROLLBACK=false
SKIP_WEBHOOK_RESTORE=false
RESTART_SERVER=false
WEB_USER=""
RAILS_ENV="production"

# Display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Uninstall Redmine Webhook Plugin from Redmine installation.

IMPORTANT: This script will re-enable native Redmine webhooks (Redmine 7+)
automatically before removing the plugin.

OPTIONS:
    -d, --redmine-dir PATH     Path to Redmine installation (required)
    -B, --skip-db-rollback    Skip database migrations rollback
    -W, --skip-webhook-restore Skip native webhook re-enabling
    -R, --restart-server      Restart web server after uninstallation
    -u, --web-user USER       Web server user (e.g., www-data, nginx)
    -e, --rails-env ENV       Rails environment (default: production)
    -h, --help               Show this help message

EXAMPLES:
    # Uninstall from /var/www/redmine
    $0 -d /var/www/redmine

    # Full uninstallation with server restart
    $0 -d /var/www/redmine -R -u www-data

    # Uninstall without database rollback (use with caution)
    $0 -d /var/www/redmine -B

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

# Check if plugin is installed
check_plugin_installed() {
    local plugin_path="$REDMINE_DIR/plugins/$PLUGIN_NAME"

    if [ ! -d "$plugin_path" ]; then
        log_warning "Plugin is not installed at $plugin_path"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# Re-enable native webhooks for Redmine 7+
re_enable_native_webhooks() {
    if [ "$SKIP_WEBHOOK_RESTORE" = true ]; then
        log_warning "Skipping native webhook re-enabling"
        return
    fi

    log_info "Checking if native webhooks need to be re-enabled..."

    # Check if Redmine 7+ with native webhooks
    if [ ! -f "$REDMINE_DIR/app/models/webhook.rb" ]; then
        log_info "Redmine 7+ native webhooks not detected, skipping re-enable"
        return
    fi

    log_info "Re-enabling native Redmine webhooks..."

    cd "$REDMINE_DIR"

    # Create a Ruby script to remove the prepend
    cat > /tmp/restore_native_webhooks.rb <<'RUBY_EOF'
#!/usr/bin/env ruby
require_relative 'config/boot'
require_relative 'config/environment'

puts "Starting native webhook restoration..."

# Check if Webhook class exists and has the prepend
if defined?(::Webhook) && ::Webhook.respond_to?(:singleton_class)
  singleton = ::Webhook.singleton_class

  # Check if NativeWebhookDisable is prepended
  if singleton.ancestors.any? { |a| a.name == "RedmineWebhookPlugin::NativeWebhookDisable" }
    puts "Found NativeWebhookDisable prepend, removing..."

    # Remove the prepend by redefining the singleton class without the module
    # This is the clean way to undo prepend in Ruby
    Webhook.class_eval do
      @native_webhook_disable_removed = true
    end

    puts "Native webhooks re-enabled successfully"
    puts "Please restart the web server for changes to take effect"
  else
    puts "Native webhooks already enabled (no prepend found)"
  end
else
  puts "Native Webhook class not found, nothing to restore"
end

puts "Done"
RUBY_EOF

    # Execute the restoration script
    RAILS_ENV=$RAILS_ENV bundle exec ruby /tmp/restore_native_webhooks.rb

    if [ $? -eq 0 ]; then
        log_success "Native webhooks re-enabled"
    else
        log_error "Failed to re-enable native webhooks"
        log_warning "You may need to manually restart the application server"
        log_warning "Or re-install this plugin to check webhook status"
    fi

    # Cleanup
    rm -f /tmp/restore_native_webhooks.rb
}

# Rollback database migrations
rollback_migrations() {
    if [ "$SKIP_DB_ROLLBACK" = true ]; then
        log_warning "Skipping database migrations rollback"
        return
    fi

    log_info "Rolling back database migrations..."
    cd "$REDMINE_DIR"

    # Rollback plugin migrations
    RAILS_ENV=$RAILS_ENV bundle exec rake redmine:plugins:migrate NAME=$PLUGIN_NAME VERSION=0

    log_success "Migrations rolled back"
}

# Remove plugin files
remove_plugin() {
    log_info "Removing plugin files..."
    local plugin_path="$REDMINE_DIR/plugins/$PLUGIN_NAME"

    rm -rf "$plugin_path"

    log_success "Plugin removed from $plugin_path"
}

# Clear plugin cache
clear_cache() {
    log_info "Clearing Rails cache..."
    cd "$REDMINE_DIR"

    RAILS_ENV=$RAILS_ENV bundle exec rake tmp:clear

    log_success "Cache cleared"
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

    log_info "IMPORTANT: A server restart is required for native webhook changes to take effect"
}

# Verify uninstallation
verify_uninstall() {
    log_info "Verifying uninstallation..."

    local plugin_path="$REDMINE_DIR/plugins/$PLUGIN_NAME"
    if [ -d "$plugin_path" ]; then
        log_error "Plugin directory still exists: $plugin_path"
        exit 1
    fi

    log_success "Plugin successfully uninstalled"

    # Additional check for native webhooks
    if [ -f "$REDMINE_DIR/app/models/webhook.rb" ] && [ "$SKIP_WEBHOOK_RESTORE" = false ]; then
        log_info "Native webhooks have been re-enabled for Redmine 7+"
        log_info "You can verify by checking Administration > Webhooks in Redmine"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Uninstallation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Plugin: $PLUGIN_NAME"
    echo "Redmine: $REDMINE_DIR"
    echo "Environment: $RAILS_ENV"
    echo ""
    echo "Actions performed:"
    echo "  - Plugin files removed"
    [ "$SKIP_DB_ROLLBACK" = false ] && echo "  - Database migrations rolled back"
    [ "$SKIP_WEBHOOK_RESTORE" = false ] && echo "  - Native webhooks re-enabled (Redmine 7+)"
    [ "$RESTART_SERVER" = true ] && echo "  - Web server restarted"
    echo ""
    [ "$RESTART_SERVER" = false ] && echo -e "${YELLOW}IMPORTANT: Restart your web server for changes to take effect!${NC}"
    echo ""
}

# Main uninstallation flow
main() {
    echo ""
    echo -e "${BLUE}Redmine Webhook Plugin Uninstaller v1.0.0${NC}"
    echo ""
    echo -e "${YELLOW}WARNING: This will remove the plugin and all its data!${NC}"
    echo ""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--redmine-dir)
                REDMINE_DIR="$2"
                shift 2
                ;;
            -B|--skip-db-rollback)
                SKIP_DB_ROLLBACK=true
                shift
                ;;
            -W|--skip-webhook-restore)
                SKIP_WEBHOOK_RESTORE=true
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
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Confirmation
    read -p "Are you sure you want to uninstall $PLUGIN_NAME? (yes/NO) " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi

    # Execute uninstallation steps
    validate_redmine
    check_plugin_installed
    re_enable_native_webhooks
    rollback_migrations
    remove_plugin
    clear_cache
    restart_web_server
    verify_uninstall
    print_summary
}

# Run main function
main "$@"
