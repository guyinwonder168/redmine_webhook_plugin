# Redmine Webhook Plugin Installer & Uninstaller

This directory contains scripts for deploying the Redmine Webhook Plugin to production Redmine installations.

## ⚠️ Important: Native Webhook Handling (Redmine 7+)

**The plugin automatically disables native Redmine webhooks (v7+) to prevent duplicate delivery.**

When uninstalling:
- The **uninstaller will automatically re-enable native webhooks**
- You must restart your web server for changes to take effect
- Verify in Redmine: Administration > Webhooks

## Files

| File | Purpose |
|-------|----------|
| `install.sh` | Install the plugin to Redmine |
| `uninstall.sh` | Safely remove the plugin and restore native webhooks |

## Prerequisites

1. **Redmine version:** 5.1.0, 5.1.10, 6.1.0, or 7.0.0+
2. **Required tools:** `bash`, `tar`, `wget` or `curl`
3. **Access to:**
   - Redmine installation directory
   - Ability to restart web server
   - Database access for migrations
4. **Ruby/Bundler:** Installed and configured on Redmine server

## Installation

### Quick Install (Current Directory)

```bash
# From plugin root directory
sudo ./installer/install.sh -d /var/www/redmine -R -u www-data
```

### Install from GitHub Release

```bash
# Download specific release
sudo ./installer/install.sh -d /var/www/redmine \
  -s https://github.com/guyinwonder168/redmine_webhook_plugin/archive/refs/tags/v1.0.0-RC.tar.gz \
  -R -u www-data
```

### Install with Backup

```bash
# Backup before installation
sudo ./installer/install.sh -d /var/www/redmine \
  -s . \
  -b /backups/redmine_webhook \
  -R
```

### Install Options

| Option | Description | Default |
|---------|-------------|-----------|
| `-d, --redmine-dir PATH` | Redmine installation path | Required |
| `-s, --source PATH|URL` | Plugin source (local or URL) | Current directory |
| `-b, --backup DIR` | Backup directory | `./backups/timestamp` |
| `-B, --skip-backup` | Skip backup | false |
| `-M, --skip-migrations` | Skip DB migrations | false |
| `-R, --restart-server` | Restart web server after install | false |
| `-u, --web-user USER` | Web server user | (none) |
| `-e, --rails-env ENV` | Rails environment | production |
| `-v, --version VERSION` | Plugin version to install | 1.0.0-RC |
| `-h, --help` | Show help | - |

### What Happens During Installation

1. ✅ Validates Redmine installation
2. ✅ Checks Redmine version compatibility
3. ✅ Creates backup of existing plugin (if any)
4. ✅ Downloads plugin (if URL provided)
5. ✅ Copies plugin to Redmine `plugins/` directory
6. ✅ Installs bundle dependencies
7. ✅ Runs database migrations
8. ✅ Restarts web server (if requested)
9. ⚠️ **Disables native webhooks** (Redmine 7+)

## Uninstallation

⚠️ **WARNING:** Uninstallation will remove the plugin and rollback all database changes.

### Quick Uninstall

```bash
# Uninstall and re-enable native webhooks
sudo ./installer/uninstall.sh -d /var/www/redmine -R
```

### Uninstall with No Database Rollback

```bash
# Remove plugin but keep database tables (use with caution)
sudo ./installer/uninstall.sh -d /var/www/redmine -B
```

### Uninstall Options

| Option | Description | Default |
|---------|-------------|-----------|
| `-d, --redmine-dir PATH` | Redmine installation path | Required |
| `-B, --skip-db-rollback` | Skip database rollback | false |
| `-W, --skip-webhook-restore` | Skip native webhook re-enable | false |
| `-R, --restart-server` | Restart web server after uninstall | false |
| `-u, --web-user USER` | Web server user | (none) |
| `-e, --rails-env ENV` | Rails environment | production |
| `-h, --help` | Show help | - |

### What Happens During Uninstallation

1. ✅ Validates Redmine installation
2. ✅ Checks if plugin is installed
3. ✅ **Re-enables native webhooks** (Redmine 7+)
4. ✅ Rolls back database migrations
5. ✅ Removes plugin directory
6. ✅ Clears Rails cache
7. ✅ Restarts web server (if requested)

## Post-Installation Steps

### 1. Verify Plugin is Registered

- Login to Redmine as administrator
- Go to: **Administration > Plugins**
- Verify: "Redmine Webhook Plugin" is listed

### 2. Configure Webhook Endpoints

- Go to: **Administration > Webhook Endpoints**
- Click: **New Webhook Endpoint**
- Configure:
  - Name: Descriptive name (e.g., "Production Slack")
  - URL: Your webhook destination (e.g., `https://hooks.slack.com/services/...`)
  - Events: Select which events trigger the webhook
  - Enabled: Check to activate
- Save

### 3. Test Webhook

- Create a test issue or time entry
- Go to: **Administration > Webhook Deliveries**
- Verify: Delivery appears with status "Success" or "Failed"

### 4. Monitor Deliveries

- Go to: **Administration > Webhook Deliveries**
- Filter by: endpoint, status, date range
- View: Details of each delivery (request/response)
- Replay: Failed deliveries with one click

## Troubleshooting

### Plugin Not Appearing in Redmine

1. Check permissions:
   ```bash
   ls -la /var/www/redmine/plugins/redmine_webhook_plugin
   # Should be owned by web user (e.g., www-data)
   chown -R www-data:www-data /var/www/redmine/plugins/redmine_webhook_plugin
   ```

2. Check migrations:
   ```bash
   cd /var/www/redmine
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
   ```

3. Restart web server:
   ```bash
   systemctl reload apache2
   # or
   systemctl restart puma
   ```

### Migrations Fail

1. Check database connection:
   ```bash
   cd /var/www/redmine
   RAILS_ENV=production bundle exec rake db:migrate:status
   ```

2. Check for pending migrations:
   ```bash
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate:status
   ```

3. Rollback and retry:
   ```bash
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin VERSION=0
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
   ```

### Native Webhooks Still Disabled After Uninstall

If native webhooks are still disabled after running the uninstaller:

1. Restart web server (Ruby class changes need restart):
   ```bash
   systemctl restart puma
   # or
   systemctl reload apache2
   ```

2. Manually verify in Redmine:
   - Go to: **Administration > Webhooks**
   - If menu appears, native webhooks are enabled

3. Reinstall plugin and uninstall again:
   ```bash
   ./installer/install.sh -d /var/www/redmine
   ./installer/uninstall.sh -d /var/www/redmine
   ```

## Security Notes

- ⚠️ **Webhook URLs:** Use HTTPS with valid certificates
- ⚠️ **Authentication:** Consider adding API keys or HMAC signatures
- ⚠️ **Web User:** Plugin runs as Redmine web user
- ⚠️ **Permissions:** Review who can configure endpoints

## Backup Strategy

### Before Installation

Always create a backup:

```bash
# Backup Redmine files
tar -czf redmine-backup-$(date +%Y%m%d).tar.gz /var/www/redmine

# Backup database
cd /var/www/redmine
RAILS_ENV=production bundle exec rake db:dump
```

### After Installation

Test thoroughly before production use:

1. Create test issue
2. Verify webhook delivery
3. Check logs: `/var/log/redmine/production.log`
4. Monitor: **Administration > Webhook Deliveries**

## Support

- **Documentation:** https://github.com/guyinwonder168/redmine_webhook_plugin/releases/tag/v1.0.0-RC
- **Issues:** https://github.com/guyinwonder168/redmine_webhook_plugin/issues
- **AGENTS.md:** Developer guide for this plugin

## Version History

| Version | Date | Changes |
|---------|--------|----------|
| 1.0.0-RC | 2026-02-03 | First release candidate |
