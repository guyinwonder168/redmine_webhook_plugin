# How to Test Redmine Plugin with Podman

Complete guide for running Redmine plugin tests using Podman containers. This setup supports testing against multiple Redmine versions (5.1.0, 5.1.10, 6.1.0) with an optional 7.0.0-dev smoke run for native webhook compatibility.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Workspace Structure](#workspace-structure)
- [Building Container Images](#building-container-images)
- [Running Tests](#running-tests)
- [Running Redmine Web Server (Browser Testing)](#running-redmine-web-server-browser-testing)
- [Manual UI Testing (Browser)](#manual-ui-testing-browser)
- [Troubleshooting Database Issues](#troubleshooting-database-issues)
- [Common Problems & Solutions](#common-problems--solutions)
- [SELinux Considerations](#selinux-considerations)
- [Container Cleanup](#container-cleanup)
- [Advanced Usage](#advanced-usage)

---

## Overview

This testing strategy uses Podman to create isolated Ruby environments for each Redmine version. The container mounts your local source code (both Redmine core and plugin) so code changes are immediately reflected in tests.

**Key benefits:**
- No local Ruby installation required
- Consistent Ruby versions across development environments
- Isolated test environments per Redmine version
- Fast test iteration with bind-mounted source code

---

## Prerequisites

### System Requirements

- **Podman** 4.0 or later
- **bash** 4.0+ for test scripts
- **~2GB** free disk space for container images and bundle cache
- **~8GB** RAM (for running containers with multiple Ruby processes)

### Verify Podman Installation

```bash
podman --version
# Expected output: podman version 4.x.x

podman ps
# Should run without errors (may show empty list)
```

### Install Podman (if needed)

**Fedora/RHEL/CentOS:**
```bash
sudo dnf install podman
```

**Debian/Ubuntu:**
```bash
sudo apt-get install podman
```

**Arch Linux:**
```bash
sudo pacman -S podman
```

---

## Workspace Structure

Ensure your workspace follows this layout:

```
/media/eddy/hdd/Project/redmine_webhook_plugin/
├── .redmine-test/
│   ├── redmine-5.1.0/           # Redmine 5.1-stable source
│   ├── redmine-5.1.10/          # Redmine 5.1.10 source
│   └── redmine-6.1.0/           # Redmine 6.1.0 source (Rails 8)
├── .bundle-cache/              # Gem cache (created automatically)
│   ├── 5.1.0/
│   ├── 5.1.10/
│   └── 6.1.0/
├── app/
├── config/
├── db/
├── lib/
├── test/
├── tools/
│   ├── docker/Containerfile.redmine
│   ├── dev/start-redmine.sh
│   ├── dev/stop-redmine.sh
│   └── test/run-test.sh
└── AGENTS.md
```

**IMPORTANT:** All paths in Podman commands MUST use **absolute paths** (no relative paths like `./.redmine-test/redmine-5.1.0`).

---

## Building Container Images

Build container images for each Redmine version. This is a one-time setup (rebuild only when Ruby version changes or system libraries update).

### Build All Images

From the plugin root directory:

```bash
# Build image for Redmine 5.1.0 (Ruby 3.2.2)
podman build -f /media/eddy/hdd/Project/redmine_webhook_plugin/tools/docker/Containerfile.redmine -t redmine-dev:5.1.0 \
  --build-arg RUBY_VERSION=3.2.2 .

# Build image for Redmine 5.1.10 (Ruby 3.2.2)
podman build -f /media/eddy/hdd/Project/redmine_webhook_plugin/tools/docker/Containerfile.redmine -t redmine-dev:5.1.10 \
  --build-arg RUBY_VERSION=3.2.2 .

# Build image for Redmine 6.1.0 (Ruby 3.3.4)
podman build -f /media/eddy/hdd/Project/redmine_webhook_plugin/tools/docker/Containerfile.redmine -t redmine-dev:6.1.0 \
  --build-arg RUBY_VERSION=3.3.4 .
```

### Verify Images

```bash
podman images | grep redmine-dev
```

Expected output:
```
redmine-dev  5.1.0   abc123...  5 minutes ago  850MB
redmine-dev  5.1.10  def456...  5 minutes ago  850MB
redmine-dev  6.1.0   ghi789...  5 minutes ago  870MB
```

---

## Running Tests

### Quick Method (Recommended)

Use the provided shell scripts for quick test runs:

```bash
# Test against Redmine 5.1.0
VERSION=5.1.0 tools/test/run-test.sh

# Test against Redmine 5.1.10
VERSION=5.1.10 tools/test/run-test.sh

# Test against Redmine 6.1.0
VERSION=6.1.0 tools/test/run-test.sh
```

The first run downloads Redmine into `.redmine-test/`. Ensure `curl` or `wget` is available.

### Manual Method (Full Control)

Run tests manually with complete Podman command. **Always use absolute paths.**

#### Example: Redmine 5.1.0

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'
```

#### Example: Redmine 6.1.0 (Rails 8 - Different DB Setup)

**Note:** Redmine 6.1.0 uses `db:schema:load` instead of `db:migrate` due to Rails 8 migration handling differences.

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop RAILS_ENV=test || true; \
    bundle exec rake db:create db:schema:load RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'
```

---

## Running Redmine Web Server (Browser Testing)

For manual testing with a browser, use the unified launcher script that supports all Redmine versions.

### Start Redmine Server

```bash
# Show help
tools/dev/start-redmine.sh

# Start specific version
tools/dev/start-redmine.sh 5.1.0      # Port 3000
tools/dev/start-redmine.sh 5.1.10     # Port 3001
tools/dev/start-redmine.sh 6.1.0      # Port 3002
tools/dev/start-redmine.sh 7.0.0-dev  # Port 3003

# Start with dummy project data
tools/dev/start-redmine.sh 5.1.0 --seed      # Start 5.1.0 with dummy projects
tools/dev/start-redmine.sh 5.1.10 --seed     # Start 5.1.10 with dummy projects
tools/dev/start-redmine.sh 6.1.0 --seed      # Start 6.1.0 with dummy projects
tools/dev/start-redmine.sh 7.0.0-dev --seed  # Start 7.0.0-dev with dummy projects

# Start all versions at once
tools/dev/start-redmine.sh all

# Start all with dummy projects
tools/dev/start-redmine.sh all --seed
```

### Access Redmine

Once started, access Redmine in your browser:

- **Redmine 5.1.0:**    http://localhost:3000
- **Redmine 5.1.10:**   http://localhost:3001
- **Redmine 6.1.0:**    http://localhost:3002
- **Redmine 7.0.0-dev:** http://localhost:3003

**Default credentials:**
- Username: `admin`
- Password: `admin` (5.1.x)
- Password: `Admin1234!` (6.1.0, 7.0.0-dev)

### Dummy Project Data (Optional)

When starting with `--seed` flag, 5 dummy projects are automatically created for testing webhook project filtering:

**Projects Created:**
- Marketing Website (marketing-web)
- Mobile App (mobile-app)
- API Services (api-services)
- Ops Tools (ops-tools)
- Documentation (docs)

**Why Use Dummy Data:**
- Webhook endpoints have a "Projects" multi-select field
- Test project-specific webhook filtering without manual setup
- Projects appear in the dropdown when creating/editing webhook endpoints

**Example Workflow with Seeding:**
```bash
# Start Redmine with dummy projects
tools/dev/start-redmine.sh 5.1.0 --seed

# Log in to Redmine
# Navigate to Administration → Webhooks → New Endpoint

# Projects field will show all 5 dummy projects
# Select specific projects to filter webhook events
```

**Note:** Seeding is optional. You can also create projects manually through Redmine's UI.

### Server Management

```bash
# View running containers
tools/dev/start-redmine.sh status

# View logs for specific version
tools/dev/start-redmine.sh logs 5.1.0
tools/dev/start-redmine.sh logs 5.1.10
tools/dev/start-redmine.sh logs 6.1.0
tools/dev/start-redmine.sh logs 7.0.0-dev

# Stop all containers
tools/dev/stop-redmine.sh

# Stop and remove container images (forces rebuild on next start)
tools/dev/stop-redmine.sh --images

# Complete cleanup (containers + images)
tools/dev/stop-redmine.sh --clean-all

# Or use the launcher script
tools/dev/start-redmine.sh stop
```

### Features

- **Automatic setup:** Gems, database, and plugin migrations are handled automatically
- **Optional seeding:** Use `--seed` flag to create dummy project data for testing
- **Environment fixes:** Proper `BUNDLE_APP_CONFIG` and `db:environment:set` for Rails 6.1
- **Background containers:** Runs in detached mode with logging
- **Color-coded status:** Visual feedback for running/stopped containers
- **Port mapping:** Each version uses a different port (3000, 3001, 3002, 3003)
- **Clean shutdown:** `tools/dev/stop-redmine.sh` supports container and image removal

### Manual Testing Workflow

**Basic Testing:**
1. **Start desired version:** `tools/dev/start-redmine.sh 5.1.0`
2. **Open browser:** http://localhost:3000
3. **Log in:** admin / admin (5.1.x) or admin / Admin1234! (6.1.0, 7.0.0-dev)
4. **Navigate to:** Administration → Webhooks
5. **Test plugin functionality** in UI
6. **View logs:** `tools/dev/start-redmine.sh logs 5.1.0`
7. **Stop server:** `tools/dev/stop-redmine.sh`

**With Dummy Project Data:**
1. **Start with seeding:** `tools/dev/start-redmine.sh 5.1.0 --seed`
2. **Open browser:** http://localhost:3000
3. **Log in:** admin / admin (5.1.x) or admin / Admin1234! (6.1.0, 7.0.0-dev)
4. **Navigate to:** Projects tab (verify 5 projects exist)
5. **Create webhook endpoint:** Administration → Webhooks → New Endpoint
6. **Select projects:** Use the Projects multi-select dropdown
7. **Test filtering:** Select specific projects (e.g., "Mobile App" only)
8. **Save endpoint:** Verify project selections are saved
9. **Stop server:** `tools/dev/stop-redmine.sh`

---

### Test Workflow for Development

1. **Make code changes** in `/media/eddy/hdd/Project/redmine_webhook_plugin`
2. **Run test script** for relevant Redmine version: `VERSION=5.1.0 tools/test/run-test.sh`
3. **Review results** - container exits with non-zero status on failure
4. **Fix issues** and repeat step 2

**Why this works fast:**
- Gem cache is preserved (`.bundle-cache/` directory)
- Source code is bind-mounted (no copy overhead)
- `bundle check` skips reinstall if gems are unchanged
- `--rm` flag cleans up container after test run

---

## Manual UI Testing (Browser)

This chapter provides detailed guidance for manually testing the Webhook Plugin Admin UI in a browser. For Redmine server startup, see [Running Redmine Web Server (Browser Testing)](#running-redmine-web-server-browser-testing) above.

### What You Should See

After logging in as admin, verify the plugin menu items appear:

**Administration Menu Structure:**
```
Administration
├── Plugins
├── Settings
├── Users
├── Groups
├── Roles and permissions
├── ...
├── Webhook Endpoints      <-- Should appear here
├── Webhook Deliveries      <-- Should appear here
└── ...
```

### Creating Webhook Endpoints

#### Step 1: Navigate to Endpoints Page

Go to: **Administration → Webhook Endpoints**

**Expected Page Elements:**
- Page title: "Webhook Endpoints"
- "New Endpoint" link with "+" icon
- Table columns:
  - Name
  - URL
  - Enabled
  - Actions (Edit, Test, Toggle, Delete)

#### Step 2: Create a New Endpoint

1. Click: **"New Endpoint"**
2. Fill in the required form fields:

**Basic Settings:**
- **Name:** Text field (required) - e.g., "Production Slack"
- **URL:** Text field (required) - e.g., `http://localhost:8080`
- **Enabled:** Checkbox - Checked by default
- **Payload Mode:** Select (Minimal / Full)

**Webhook User (Authentication):**
- **Webhook User:** Select a Redmine user from dropdown
- When set, webhook requests include `X-Redmine-API-Key` header for authentication

**Projects (Filtering):**
- **Projects:** Multi-select dropdown
- Hint: "Empty = all projects"
- Available projects (if started with `--seed`):
  - Marketing Website (marketing-web)
  - Mobile App (mobile-app)
  - API Services (api-services)
  - Ops Tools (ops-tools)
  - Documentation (docs)

**Events:**
```
Events
├── Issues
│   ├── Created  ☐
│   ├── Updated  ☐
│   └── Deleted  ☐
└── Time Entries
    ├── Created  ☐
    ├── Updated  ☐
    └── Deleted  ☐
```

**Retry Policy:**
```
Retry Policy
├── Max Attempts: [5]
├── Base Delay (seconds): [60]
└── Max Delay (seconds): [3600]
```

**Request Options:**
```
Request Options
├── Timeout (seconds): [30]
└── Verify SSL: ☑
```

 3. Click: **"Save"**

#### Webhook Test Server Overview

The webhook test server (`tools/webhook_test_server.py`) is a lightweight HTTP server that receives and logs webhook requests from Redmine. It's essential for end-to-end testing to verify that webhooks are being sent correctly.

**When to use it:**
- Developing or testing webhook endpoints
- Verifying webhook payload structure
- Debugging delivery failures
- Checking custom headers and authentication
- Testing project-specific webhook filtering

**Features:**

| Feature | Description |
|---------|-------------|
| HTTP endpoint | Receives POST requests on configurable port (default: 8080) |
| Console logging | Colorized, real-time display of incoming webhook requests |
| Web UI | Browser-based interface at `http://localhost:<port>/` showing recent events |
| Log persistence | Saves all received webhooks to `webhook_events.json` |
| Health check | `/health` endpoint for server availability verification |
| Custom port | Run multiple servers on different ports (e.g., 8080, 8081) |

**Starting server:**

```bash
# Default port (8080)
cd tools
python3 webhook_test_server.py

# Custom port
python3 webhook_test_server.py 8081

# From plugin root
python3 tools/webhook_test_server.py 8080
```

**Startup output:**
```
============================================================
🎣 WEBHOOK TEST SERVER
============================================================

Starting webhook test server...
  Port: 8080
  Health check: http://localhost:8080/health
  Web UI: http://localhost:8080/
  Log file: /media/eddy/hdd/Project/redmine_webhook_plugin/tools/webhook_events.json

============================================================
Waiting for webhook requests...
Press Ctrl+C to stop.
============================================================
```

**Web UI interface:**

Visit `http://localhost:8080/` in your browser to view:
- Last 10 webhook events (with timestamps, methods, paths, payloads)
- Real-time updates as webhooks arrive
- Colorized console-style display for easy reading

**Understanding console output:**

When a webhook arrives, you'll see:

```
============================================================
📨 WEBHOOK RECEIVED - 2026-02-04T15:30:45.123456
============================================================
Method:   POST
Path:     /
Headers:
  Host: localhost:8080
  Content-Type: application/json
  X-Redmine-Webhook-Id: 550e8400-e29b...
  X-Webhook-Signature: sha256=abc123...

Body (1247 bytes):
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "issue",
  "action": "created",
  "occurred_at": "2026-02-04T15:30:45.000000Z",
  "resource": {
    "type": "issue",
    "id": 1,
    "subject": "Test webhook",
    ...
  },
  "actor": {
    "id": 1,
    "login": "admin",
    "name": "Administrator"
  }
}

💾 Saved to: webhook_events.json
============================================================
```

**Checking JSON log file:**

All received webhooks are persisted to `tools/webhook_events.json`:

```json
[
  {
    "timestamp": "2026-02-04T15:30:45.123456",
    "method": "POST",
    "path": "/",
    "headers": {
      "Host": "localhost:8080",
      "Content-Type": "application/json",
      "X-Redmine-Webhook-Id": "550e8400-e29b..."
    },
    "body": "{ \"event_id\": ... }",
    "content_type": "application/json",
    "content_length": 1247
  },
  ...
]
```

Useful for:
- Analyzing webhook history
- Comparing multiple webhook deliveries
- Exporting webhook payloads for testing

**Health check:**

Verify server is running:

```bash
curl http://localhost:8080/health
```

Expected response:
```json
{
  "status": "ok",
  "server": "webhook-test-server",
  "timestamp": "2026-02-04T15:30:45.000000Z"
}
```

**Running multiple test servers:**

For testing multiple webhook endpoints simultaneously, run servers on different ports:

```bash
# Terminal 1 - Production endpoint simulator
python3 tools/webhook_test_server.py 8080

# Terminal 2 - Staging endpoint simulator  
python3 tools/webhook_test_server.py 8081

# Terminal 3 - Development endpoint simulator
python3 tools/webhook_test_server.py 8082
```

Then create webhook endpoints in Redmine pointing to:
- `http://localhost:8080` (production simulator)
- `http://localhost:8081` (staging simulator)
- `http://localhost:8082` (development simulator)

**Troubleshooting:**

**Issue: Server won't start (Address already in use)**
```bash
# Check what's using the port
lsof -i :8080
# Or
netstat -tulpn | grep 8080

# Kill the process or use a different port
python3 tools/webhook_test_server.py 8081
```

**Issue: Webhook not received**

1. **Verify server is listening:**
   ```bash
   curl http://localhost:8080/health
   ```

2. **Check Redmine endpoint URL:**
   - Go to Administration → Webhook Endpoints
   - Verify URL matches server port (e.g., `http://localhost:8080`)
   - Check that endpoint is **enabled**

3. **Verify event types:**
   - Check that event checkboxes match what you're triggering
   - Example: Creating an issue triggers "Issues → Created" event

4. **Check Redmine delivery logs:**
   - Go to Administration → Webhook Deliveries
   - Look for failed deliveries with error messages

**Issue: JSON log file corrupted**

The server creates a new log file on each run. If corrupted:

```bash
# Remove corrupted log and restart
rm -f tools/webhook_events.json
python3 tools/webhook_test_server.py 8080
```

**Issue: Can't access web UI from container**

If Redmine is running in a Podman container and you're trying to access the web UI:

1. **Use host IP instead of localhost:**
   ```bash
   # Find your host IP
   ip addr show | grep inet
   
   # Update webhook endpoint URL to use host IP
   # Example: http://192.168.1.100:8080
   ```

2. **Or expose port from container:**
   ```bash
   # The Redmine container doesn't need to access test server
   # Test server runs on host, Redmine sends requests to it
   # Just ensure Redmine can reach your host IP
   ```

---

### Testing Webhook Delivery (End-to-End)

#### Step 3: Start Webhook Test Server

⚠️ **IMPORTANT:** This step is REQUIRED for complete testing

To verify that webhooks are actually being sent, run the webhook test server:

```bash
cd tools
python3 webhook_test_server.py 8080
```

The server will:
- Listen for POST requests on port 8080
- Log all incoming webhook calls to console
- Show webhook data in JSON format
- Save logs to `webhook_events.json`

#### Step 4: Trigger a Webhook

1. **Go to:** Projects → Marketing Website (or any selected project)
2. **Create a new issue:**
   - Enter subject: "Test webhook"
   - Enter description: "Testing webhook delivery"
   - Click: **"Create"**

#### Step 5: Verify Webhook Was Delivered

**Check webhook test server console:**
You should see a JSON payload logged:
```json
{
  "event_id": "...",
  "event_type": "issue",
  "action": "created",
  "occurred_at": "2026-02-04T...",
  "resource": { ... },
  "actor": { ... }
}
```

**Check Redmine delivery logs:**
1. Go to: **Administration → Webhook Deliveries**
2. You should see a delivery with status: **"Success"**

### Managing Redmine Containers

The `tools/dev/start-redmine.sh` script provides several management commands:

#### Show Running Status

```bash
tools/dev/start-redmine.sh status
```

Shows which Redmine versions are currently running with their ports.

#### View Logs

```bash
# Show logs for specific version
tools/dev/start-redmine.sh logs 5.1.0

# Or other versions
tools/dev/start-redmine.sh logs 6.1.0
```

#### Stop All Containers

```bash
tools/dev/start-redmine.sh stop
```

This stops all Redmine containers and removes them.

### Required Testing Components

For complete end-to-end testing, you MUST have ALL THREE components running:

| Component | Status | Port | Purpose |
|-----------|--------|-------|---------|
| Redmine server | ⚠️ REQUIRED | 3000-3003 | Admin UI for webhook configuration |
| Dummy projects | ⚠️ REQUIRED | N/A | Projects for webhook filtering test |
| Webhook test server | ⚠️ REQUIRED | 8080 | Receive and log webhook calls |

⚠️ **ALL THREE MUST BE RUNNING FOR COMPLETE TESTING!**

Without dummy projects, you can't test the "Projects" multi-select field in webhook form.
Without webhook test server, you can't verify that Redmine is actually sending webhook calls.

### Troubleshooting

#### Issue: "Webhook Endpoints" menu item not visible

**Check 1: Verify Plugin is Registered**
```bash
podman exec redmine-5.1.0 bash -lc '
  cd /redmine
  bundle exec rails runner "puts Redmine::Plugin.find(:redmine_webhook_plugin).name"
'
```
Expected output: "Redmine Webhook Plugin"

**Check 2: Verify Database Migration**
```bash
podman exec redmine-5.1.0 bash -lc '
  cd /redmine
  bundle exec rails runner "puts RedmineWebhookPlugin::Webhook::Endpoint.table_name"
'
```
Expected output: "webhook_endpoints"

**Check 3: Restart Container**
```bash
# Stop and restart
tools/dev/start-redmine.sh stop
tools/dev/start-redmine.sh 5.1.0 --seed
```

#### Issue: Container won't start / Port already in use

**Solution:**
The script automatically uses different ports for each version. If you still have conflicts, check what's using the port:

```bash
podman ps
```

Then stop conflicting containers with `tools/dev/start-redmine.sh stop`.

#### Issue: Missing dummy projects in form

**Solution:**
Start Redmine with `--seed` flag:
```bash
tools/dev/start-redmine.sh 5.1.0 --seed
```

This will create 5 dummy projects using `db/seeds.rb`:
- Marketing Website
- Mobile App
- API Services
- Ops Tools
- Documentation

#### Issue: Webhook delivery not received

**Check 1: Verify webhook test server is running**
```bash
# Check if process is listening
curl http://localhost:8080
```

**Check 2: Verify endpoint is enabled**
- Go to Administration → Webhook Endpoints
- Check that the endpoint's "Enabled" checkbox is checked

**Check 3: Check delivery logs**
- Go to Administration → Webhook Deliveries
- Look for failed deliveries with error messages

### Testing Checklist

Use this checklist to manually verify Webhook Plugin functionality:

#### Admin Menu Integration
- [ ] Admin menu shows "Webhook Endpoints" link
- [ ] Admin menu shows "Webhook Deliveries" link
- [ ] Clicking "Webhook Endpoints" opens the index page
- [ ] Clicking "Webhook Deliveries" opens the index page

#### Endpoints Management
- [ ] Page shows table with columns: Name, URL, Enabled, Actions
- [ ] "New Endpoint" link present
- [ ] Create form displays all fields correctly
- [ ] Can create new endpoint
- [ ] Can edit existing endpoint
- [ ] Can delete endpoint
- [ ] Toggle enabled/disabled works

#### Endpoint Form Fields
- [ ] Name field accepts text and is required
- [ ] URL field accepts text and is required
- [ ] Payload Mode selector shows Minimal/Full options
- [ ] Webhook User dropdown shows users
- [ ] Projects multi-select shows available projects
- [ ] Projects field shows hint "Empty = all projects"
- [ ] Events checkboxes work for Issues (Created, Updated, Deleted)
- [ ] Events checkboxes work for Time Entries (Created, Updated, Deleted)
- [ ] Retry Policy fields have correct defaults
- [ ] Request Options fields have correct defaults

#### Webhook Delivery
- [ ] Test delivery button creates a delivery entry
- [ ] Creating an issue triggers webhook
- [ ] Webhook test server receives payload
- [ ] Delivery status shows "Success" in Webhook Deliveries page
- [ ] Failed deliveries show error messages

#### User Experience
- [ ] All i18n labels display correctly
- [ ] Form validation works for missing required fields
- [ ] API key warning displays when webhook user has no key
- [ ] Page loads without errors in browser console

### Summary

The unit and functional tests verify this, but manual browser testing lets you:
1. See actual UI
2. Verify menu integration visually
3. Test full user workflow
4. Check responsive design
5. Verify i18n labels in context
6. Test webhook delivery end-to-end

All menu entries, routes, controllers, and views are implemented and tested. Use `tools/dev/start-redmine.sh` to quickly spin up Redmine and navigate to Administration → Webhook Endpoints to see it in action!

---

## Troubleshooting Database Issues

### Problem 1: SQLite Database is "Corrupted" or "Noisy"

**Symptoms:**
```
ActiveRecord::StatementInvalid: SQLite3::CorruptException: database disk image is malformed
```
or
```
SQLite3::BusyException: database is locked
```

**Root Causes:**
1. **File locking conflicts** with bind-mounted SQLite files
2. **WAL (Write-Ahead Logging) mode** creates `.db-shm` and `.db-wal` files that may not sync properly
3. **Stale lock files** from crashed containers
4. **Multiple test processes** accessing the same DB file
5. **Filesystem issues** with overlayfs and SQLite

### Solution 1: Force Database Recreate (First Try)

The test scripts already include `db:drop` at the start. If that fails, try manually:

```bash
# Remove database files manually
rm -f /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/redmine_test.sqlite3*
rm -f /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/redmine_test.sqlite3-shm
rm -f /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/redmine_test.sqlite3-wal

# Run test again
VERSION=5.1.0 tools/test/run-test.sh
```

### Solution 2: Use Tmpfs for Database (Recommended)

Mount the database directory as tmpfs (in-memory) to avoid filesystem locking issues:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  --mount type=tmpfs,destination=/redmine/db,tmpfs-size=512M \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'
```

**Why this works:**
- Database is created in RAM (no persistent file)
- No file locking issues with overlayfs
- Faster test execution (no disk I/O)
- Fresh database every run (no noise from previous runs)

### Solution 3: Use In-Memory SQLite

Modify the database config to use pure in-memory SQLite:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: \":memory:\"\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'
```

**Note:** In-memory SQLite may have issues with some Redmine features that rely on specific SQLite extensions. Use tmpfs (Solution 2) if in-memory mode fails.

### Solution 4: Disable WAL Mode

If tests fail with WAL-related errors, disable it in the test configuration:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    echo "config.active_record.sqlite3_production_warning = false" >> config/environments/test.rb; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'
```

### Solution 5: Fix Permission Issues

Sometimes database files have wrong permissions from previous container runs:

```bash
# Fix ownership for Redmine 5.1.0
sudo chown -R $(id -u):$(id -g) /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/

# Or use podman unshare for rootless Podman
podman unshare chown -R 1000:1000 /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/
```

### Solution 6: Use Separate Test Database Names

If running multiple tests in parallel, use unique database names:

```bash
DB_NAME="db/redmine_test_$(date +%s).sqlite3"
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc "set -euo pipefail; cd /redmine; \
    printf \"test:\n  adapter: sqlite3\n  database: ${DB_NAME}\n  pool: 5\n  timeout: 5000\n\" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test -S rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test"
```

---

## Common Problems & Solutions

### Problem: `permission denied` when mounting volumes

**Symptom:**
```
Error: container create failed: container_linux.go:380: starting container process caused: process_linux.go:545: container init caused: rootfs_linux.go:76: mounting "/media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0" to rootfs at "/redmine" caused: permission denied
```

**Solutions:**

1. **Check file permissions:**
   ```bash
   ls -la /media/eddy/hdd/Project/redmine_webhook_plugin/
   ```

2. **Use `podman unshare` to fix permissions:**
   ```bash
   podman unshare chown -R $(id -u):$(id -g) /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/
   podman unshare chown -R $(id -u):$(id -g) /media/eddy/hdd/Project/redmine_webhook_plugin/
   ```

3. **Use SELinux label (if SELinux is enforcing):**
   ```bash
   podman run --rm -it \
     -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:Z \
     ...
   ```

### Problem: `test_helper` not found

**Symptom:**
```
cannot load such file -- test_helper (LoadError)
```

**Solution:**
The test scripts already set `RUBYLIB` environment variable. Ensure you're using the full command with `-e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test`:

```bash
podman run ... \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  ...
```

### Problem: Bundle install fails with network errors

**Symptom:**
```
Could not find gem 'rails' in rubygems repository
```

**Solution:**
1. Check internet connectivity inside container:
   ```bash
   podman run --rm -it redmine-dev:5.1.0 ping -c 3 rubygems.org
   ```

2. If behind a proxy, configure RubyGems:
   ```bash
   podman run --rm -it \
     -e http_proxy=http://proxy:port \
     -e https_proxy=http://proxy:port \
     redmine-dev:5.1.0 \
     bash -lc "gem sources -a https://rubygems.org"
   ```

3. Use cached gems if available (bundle cache is mounted):

### Problem: Container exits immediately with code 127

**Symptom:**
Container exits without any output.

**Solution:**
Check if command is available in container:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  redmine-dev:5.1.0 \
  bash -lc "which bundle"
```

If `which bundle` returns nothing, the bundle is not installed. Run:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc "cd /redmine && bundle install"
```

### Problem: Tests run but report 0 tests executed

**Symptom:**
```
0 runs, 0 assertions, 0 failures, 0 errors, 0 skips
```

**Solution:**

1. Verify test files exist:
   ```bash
   ls -la /media/eddy/hdd/Project/redmine_webhook_plugin/test/
   ```

2. Check test file naming convention (must end with `_test.rb`):
   ```bash
   find /media/eddy/hdd/Project/redmine_webhook_plugin/test -name "*_test.rb"
   ```

3. Verify plugin is symlinked correctly:
   ```bash
   ls -la /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/plugins/
   ```

### Problem: Redmine 6.1.0 migration failures

**Symptom:**
```
StandardError: An error has occurred, this and all later migrations canceled:
Directly inheriting from ActiveRecord::Migration[6.1] is not supported
```

**Solution:**
Redmine 6.1.0 uses `db:schema:load` instead of `db:migrate` for tests. The provided `tools/test/run-test.sh` handles this correctly when `VERSION=6.1.0`.

Ensure you're using:
```bash
VERSION=6.1.0 tools/test/run-test.sh
```

### Problem: Redmine 6.1.0 plugin migration failures (Rails 8 schema_migrations issue)

**Symptom:**
```
StandardError: An error has occurred, this and all later migrations canceled:
SQLite3::SQLException: table "webhook_endpoints" already exists
```

**Root Cause:**
Rails 8's `db:schema:load` creates the Redmine core schema but does not create the `schema_migrations` table that plugin migrations require to track their execution status.

**Solution:**
The `tools/test/run-test.sh` runner has been updated to handle this Rails 8 behavior:

1. After `db:schema:load`, manually create the `schema_migrations` table
2. Drop any existing plugin tables before running plugin migrations
3. This ensures clean state for plugin migrations to run properly

The fix includes these commands in the test script:
```bash
sqlite3 db/redmine_test.sqlite3 "CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR(255) NOT NULL UNIQUE PRIMARY KEY);" 2>/dev/null || true;
sqlite3 db/redmine_test.sqlite3 "CREATE UNIQUE INDEX IF NOT EXISTS unique_schema_migrations ON schema_migrations (version);" 2>/dev/null || true;
sqlite3 db/redmine_test.sqlite3 "DROP TABLE IF EXISTS webhook_endpoints;" 2>/dev/null || true;
sqlite3 db/redmine_test.sqlite3 "DROP TABLE IF EXISTS webhook_deliveries;" 2>/dev/null || true;
```

**Result:** All three Redmine versions (5.1.0, 5.1.10, 6.1.0) now pass tests consistently.

### Problem: Minitest 6 compatibility issues (Redmine 5.1.10)

**Symptom:**
```
NoMethodError: undefined method `filter' for #<Minitest::Test:0x...>
```

**Solution:**
Redmine 5.1.10 may need `minitest` pinned to version 5.x. Check if `Gemfile.local` exists in the Redmine directory:

```bash
cat /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10/Gemfile.local
```

If not present or missing the minitest pin, create it:

```bash
echo "gem 'minitest', '~> 5.0'" >> /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10/Gemfile.local
VERSION=5.1.10 tools/test/run-test.sh
```

---

## SELinux Considerations

### Problem: Volume mounts fail on SELinux-enforcing systems

**Symptom:**
```
Error: container_linux.go:380: starting container process caused: process_linux.go:545: container init caused: rootfs_linux.go:76: mounting "/path" to rootfs caused: permission denied
```

**Solution: Add SELinux labels to volume mounts**

Use `:Z` (lowercase z for shared access between containers, uppercase Z for private per-container):

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:Z \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:Z \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:Z \
  ...
```

**What `:Z` does:**
- Automatically assigns a private SELinux context to the mounted directory
- Allows the container to read/write the mounted files
- Prevents other containers from accessing these files (security isolation)

**What `:z` (lowercase) does:**
- Assigns a shared SELinux context
- Allows multiple containers to share the mounted directory
- Use this only if you need multiple containers to access the same volume

### Check SELinux status

```bash
getenforce
# Expected output: Enforcing, Permissive, or Disabled
```

If `Enforcing`, you MUST use SELinux labels.

---

## Container Cleanup

### Stop Redmine Containers

Use the stop script to stop all Redmine containers:

```bash
# Stop containers only (keep images for quick restart)
tools/dev/stop-redmine.sh

# Stop containers and remove images (forces rebuild on next start)
tools/dev/stop-redmine.sh --images

# Complete cleanup (remove both containers and images)
tools/dev/stop-redmine.sh --clean-all
```

**When to use each option:**
- **Default** - When you'll restart soon; images are kept for faster startup
- **`--images`** - When you want to rebuild from scratch (gem updates, dependency changes)
- **`--clean-all`** - Complete cleanup; everything removed

### View Running Containers

```bash
podman ps
```

### View All Containers (including stopped)

```bash
podman ps -a
```

### Remove Specific Container

```bash
podman rm <container_id>
```

### Remove All Stopped Containers

```bash
podman container prune -f
```

### Remove Volumes

```bash
# List volumes
podman volume ls

# Remove specific volume
podman volume rm <volume_name>

# Remove unused volumes
podman volume prune -f
```

### System Cleanup (Remove Everything)

```bash
# Remove all containers, images, volumes, and networks not in use
podman system prune -a --volumes -f
```

**Warning:** This removes all unused resources. Use with caution.

### Cleanup After Each Test

The test scripts use `--rm` flag, which automatically removes the container after it exits. No manual cleanup is needed after successful test runs.

However, if you cancel tests mid-run or containers crash, you may have orphaned containers:

```bash
# Remove all exited containers
podman rm -f $(podman ps -aq -f status=exited)
```

---

## Advanced Usage

### Run Single Test File

Instead of running the full test suite, run a specific test file:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec ruby -I/redmine/plugins/redmine_webhook_plugin/test \
      /redmine/plugins/redmine_webhook_plugin/test/unit/sanity_test.rb -n test_plugin_is_registered'
```

### Run Tests in Parallel

Run tests against multiple Redmine versions simultaneously:

```bash
# Run all three in parallel
VERSION=5.1.0 tools/test/run-test.sh &
PID_510=$!

VERSION=5.1.10 tools/test/run-test.sh &
PID_5110=$!

VERSION=6.1.0 tools/test/run-test.sh &
PID_610=$!

# Wait for all to complete
wait $PID_510
wait $PID_5110
wait $PID_610
```

**Note:** Use separate databases for each version to avoid locking conflicts.

### Interactive Shell in Container

For debugging, enter an interactive shell inside the container:

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash
```

Then run commands manually inside the container:
```bash
cd /redmine
bundle check
bundle install
rake db:drop db:create db:migrate RAILS_ENV=test
rake redmine:plugins:migrate RAILS_ENV=test
rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test
```

### Use PostgreSQL Instead of SQLite

For production-like testing, use PostgreSQL in a separate container:

```bash
# Start PostgreSQL container
podman run --rm -d \
  --name postgres-test \
  -e POSTGRES_DB=redmine_test \
  -e POSTGRES_USER=redmine \
  -e POSTGRES_PASSWORD=password \
  postgres:15-alpine

# Create database config
cat > /tmp/database.yml <<'YML'
test:
  adapter: postgresql
  database: redmine_test
  host: postgres-test
  username: redmine
  password: password
  encoding: utf8
  pool: 5
  timeout: 5000
YML

# Run tests with PostgreSQL
podman run --rm -it \
  --link postgres-test:postgres-test \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -v /tmp/database.yml:/redmine/config/database.yml:ro \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'

# Cleanup PostgreSQL container
podman stop postgres-test
```

### Custom Ruby Version

To test with a different Ruby version, rebuild the image:

```bash
podman build -f tools/docker/Containerfile.redmine -t redmine-dev:5.1.0-custom \
  --build-arg RUBY_VERSION=3.1.0 .
```

Then use the new image in your test command.

---

## Summary

### Key Points to Remember

1. **Always use absolute paths** when mounting volumes in Podman
2. **Use `--rm` flag** to automatically clean up containers after tests
3. **Use tmpfs for databases** to avoid corruption and improve performance
4. **Add `:Z` label** on SELinux-enforcing systems
5. **Redmine 6.1.0 uses `db:schema:load`**, not `db:migrate`
6. **Keep bundle cache** in `.bundle-cache/` directory to speed up repeated runs
7. **Clean up orphaned containers** after interrupted test runs

### Quick Reference Commands

```bash
# Build images
podman build -f tools/docker/Containerfile.redmine -t redmine-dev:5.1.0 --build-arg RUBY_VERSION=3.2.2 .

# Run tests
VERSION=5.1.0 tools/test/run-test.sh

# Fix database corruption
rm -f /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/redmine_test.sqlite3*

# Use tmpfs for database (add to podman run)
--mount type=tmpfs,destination=/redmine/db,tmpfs-size=512M

# SELinux fix
-v /path:/path:Z

# Cleanup
podman system prune -a --volumes -f
```

### Troubleshooting Decision Tree

```
Database corruption?
├─ Remove DB files manually → retry
├─ Use tmpfs mount → recommended
└─ Use in-memory SQLite → last resort

Permission errors?
├─ Check file ownership → fix with chown
├─ Use podman unshare → for rootless Podman
└─ Add :Z label → SELinux systems

Test not found?
├─ Check RUBYLIB env var → must be set
├─ Verify test file naming → must end with _test.rb
└─ Check plugin symlink → must be in plugins/

Migration errors?
├─ Redmine 5.x → use db:migrate
├─ Redmine 6.x → use db:schema:load
└─ Minitest version → pin to ~> 5.0 in Gemfile.local
```

---

## Additional Resources

- [Podman Documentation](https://docs.podman.io/)
- [SQLite Database Corruption Guide](https://sqlite.org/howtocorrupt.html)
- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)
- [Redmine Plugin Development](https://www.redmine.org/projects/redmine/wiki/Plugin_Tutorial)

---

**Last Updated:** December 26, 2025
**Maintained by:** Redmine Workspace Team
