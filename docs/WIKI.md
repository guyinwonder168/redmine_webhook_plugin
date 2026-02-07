# Redmine Webhook Plugin - Comprehensive Documentation

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage Guide](#usage-guide)
- [Admin Interface](#admin-interface)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Advanced Configuration](#advanced-configuration)
- [API Reference](#api-reference)
- [Migration & Upgrades](#migration--upgrades)
- [Changelog](#changelog)

---

## Overview

### What is Redmine Webhook Plugin?

Redmine Webhook Plugin provides outbound webhook notifications for issues and time entries in Redmine. When events occur in Redmine (like creating, updating, or deleting an issue), the plugin sends HTTP POST requests to configured external endpoints, enabling integration with third-party systems like Slack, Microsoft Teams, Jira, custom dashboards, and more.

### Key Features

| Feature | Description |
|----------|-------------|
| **Issue Webhooks** | Triggered on create, update, delete operations |
| **Time Entry Webhooks** | Triggered on time entry events |
| **Event Filtering** | Select which events trigger webhooks per endpoint |
| **Multiple Payload Modes** | minimal, standard, full for different use cases |
| **Delivery Tracking** | Monitor all webhook deliveries, view request/response |
| **Retry Logic** | Automatic retry with exponential backoff |
| **Bulk Operations** | Replay failed deliveries, export to CSV |
| **Global Pause** | Pause all webhook deliveries from settings |
| **Admin UI** | Full web interface for configuration and monitoring |
| **Redmine 7+ Compatible** | Automatically handles native webhooks to prevent duplicates |

### Supported Redmine Versions

| Version | Status | Notes |
|---------|---------|--------|
| 5.1.0 | ✅ Supported | Minimum version |
| 5.1.10 | ✅ Supported | Tested |
| 6.1.0 | ✅ Supported | Tested |
| 7.0.0+ | ✅ Supported | Handles native webhooks |

### Requirements

- **Redmine:** 5.1.0 or higher
- **Ruby:** 3.x
- **Database:** SQLite, PostgreSQL, MySQL, MariaDB
- **Web Server:** Apache, Nginx, Puma, Unicorn (any Redmine-compatible)
- **Network Access:** Outbound HTTPS to webhook endpoints

---

## Getting Started

### Quick Start (3 Steps)

1. **Install the Plugin**
   ```bash
   # Using installer script (recommended)
   sudo ./installer/install.sh -d /var/www/redmine -R -u www-data
   ```

2. **Create a Webhook Endpoint**
   - Navigate to: **Administration > Webhook Endpoints**
   - Click: **New Webhook Endpoint**
   - Configure: Name, URL, Events, and click **Save**

3. **Test the Webhook**
   - Create or update an issue in Redmine
   - Check: **Administration > Webhook Deliveries**
   - Verify: Delivery appears with status "Success"

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Redmine Server                          │
│                                                                 │
│  ┌────────────┐      ┌─────────────┐                │
│  │    Issues   │      │Time Entries │                │
│  └─────┬──────┘      └──────┬──────┘                │
│         │                     │                              │
│         ▼                     ▼                              │
│  ┌──────────────────────────────────────┐                 │
│  │  Redmine Webhook Plugin          │                 │
│  │  ┌────────────────────────────┐    │                 │
│  │  │ Webhook Dispatcher        │    │                 │
│  │  └───────────┬────────────┘    │                 │
│  │              │                    │                 │
│  │    ┌─────────┼──────────┐   │                 │
│  │    │Endpoint 1│Endpoint 2│   │                 │
│  │    │   ┌───┐│  ┌───┐   │                 │
│  │    │   │Sender│  │Sender│   │                 │
│  │    │   └───┘│  └───┘   │                 │
│  │    │    │        │        │                 │
│  │    └────┼────────┘        │                 │
│  │         │                 │                 │
│  │         ▼                 │                 │
│  │    ┌────────────────┐      │                 │
│  │    │  HTTP Client  │      │                 │
│  │    └────────────────┘      │                 │
│  └──────────────────────────────┘                 │
│         │                                  │
│         ▼                                  │
│  ┌──────────────────────────────────┐         │
│  │   External Systems               │         │
│  │   - Slack                         │         │
│  │   - Microsoft Teams                │         │
│  │   - Custom APIs                   │         │
│  │   - Dashboards                   │         │
│  └──────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### Webhook Lifecycle

```
1. Event Occurs in Redmine
   ↓
2. Plugin Captures Event (before_save, after_commit)
   ↓
3. Dispatcher Creates Delivery Record
   ↓
4. Sender Queues HTTP Request
   ↓
5. HTTP Client Sends Request (with retry logic)
   ↓
6. Response Recorded (Success/Failure)
   ↓
7. Delivery Stored in Database
   ↓
8. Visible in Admin UI
```

---

## Installation

### Method 1: Automated Installer (Recommended)

For production deployments, use the provided installer script:

```bash
# Download release
wget https://git.example.com/your-org/redmine_webhook_plugin/-/archive/v1.0.0-RC1/redmine_webhook_plugin-v1.0.0-RC1.tar.gz

# Extract
tar -xzf redmine_webhook_plugin-v1.0.0-RC1.tar.gz

# Install
cd redmine_webhook_plugin
sudo ./installer/install.sh -d /var/www/redmine -R -u www-data
```

**Installer Options:**
- `-d, --redmine-dir`: Redmine installation path (required)
- `-s, --source`: Plugin source or GitLab URL
- `-b, --backup`: Backup directory
- `-B, --skip-backup`: Skip backup
- `-M, --skip-migrations`: Skip DB migrations
- `-R, --restart-server`: Restart web server
- `-u, --web-user`: Web server user
- `-e, --rails-env`: Rails environment (default: production)

### Method 2: Manual Installation

```bash
# Clone or extract to Redmine plugins directory
cd /path/to/redmine/plugins
git clone https://git.example.com/your-org/redmine_webhook_plugin.git
# OR
tar -xzf plugin.tar.gz

# Run migrations
cd /path/to/redmine
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin

# Install dependencies
bundle install

# Restart web server
systemctl restart puma
# OR
systemctl reload apache2
```

### Installation Verification

After installation, verify the plugin is active:

1. Login to Redmine as administrator
2. Navigate to: **Administration > Plugins**
3. Look for: **Redmine Webhook Plugin** in the list
4. Verify version: **1.0.0-RC1**

### Uninstallation

To remove the plugin and re-enable native webhooks (Redmine 7+):

```bash
cd redmine_webhook_plugin
sudo ./installer/uninstall.sh -d /var/www/redmine -R
```

**⚠️ Important:** The uninstaller automatically re-enables native Redmine webhooks when removing the plugin. You must restart your web server for changes to take effect.

---

## Configuration

### Webhook Endpoints

Navigate to: **Administration > Webhook Endpoints**

#### Creating an Endpoint

1. Click **New Webhook Endpoint**
2. Fill in the required fields:

| Field | Description | Example | Required |
|--------|-------------|----------|----------|
| **Name** | Descriptive identifier | "Production Slack" | Yes |
| **URL** | HTTPS endpoint | "https://hooks.slack.com/services/..." | Yes |
| **Events** | Events to trigger | See below | At least 1 |
| **Enabled** | Activate webhook | ☑ | Yes |

#### Event Types

| Event | Triggered When | Payload Notes |
|--------|----------------|----------------|
| **Issue Created** | New issue added | Full issue data |
| **Issue Updated** | Issue modified | Changes included |
| **Issue Deleted** | Issue removed | Issue data (snapshot) |
| **Time Entry Created** | Time logged | Full time entry |
| **Time Entry Updated** | Time modified | Changes included |
| **Time Entry Deleted** | Time removed | Time entry data |

#### Event Filters

By default, endpoints receive all events. To filter:

1. Edit an endpoint
2. Under **Events**, select specific events
3. Save

**Use Case:** Create separate endpoints for different teams:
- Endpoint A: Only "Issue Created" → Project Management Team (Slack)
- Endpoint B: All events → Development Team (Microsoft Teams)

### Payload Modes

Select the appropriate payload mode based on your integration needs:

| Mode | Size | Use Case | Includes |
|-------|--------|------------|----------|
| **Minimal** | Small | Event metadata only |
| **Standard** | Medium | Essential fields + changes |
| **Full** | Large | All available data |

#### Minimal Payload Example

```json
{
  "event_id": "uuid",
  "event_type": "issue",
  "action": "created",
  "occurred_at": "2026-02-03T12:00:00Z",
  "resource_type": "Issue",
  "resource_id": 123,
  "actor": {
    "id": 1,
    "login": "admin",
    "name": "Administrator"
  },
  "redmine_url": "https://redmine.example.com/issues/123"
}
```

#### Standard Payload Example

```json
{
  "event_id": "uuid",
  "event_type": "issue",
  "action": "updated",
  "occurred_at": "2026-02-03T12:00:00Z",
  "resource_type": "Issue",
  "resource_id": 123,
  "actor": { "id": 1, "login": "admin" },
  "redmine_url": "https://redmine.example.com/issues/123",
  "issue": {
    "id": 123,
    "subject": "Bug fix needed",
    "description": "Fix authentication...",
    "status": "In Progress",
    "priority": "High",
    "assigned_to": { "id": 2, "name": "Developer" },
    "project": { "id": 5, "name": "Main Project" },
    "last_note": "Looking into this",
    "custom_fields": [ ... ]
  },
  "changes": {
    "status": { "old": "New", "new": "In Progress" },
    "assigned_to": { "old": null, "new": { "id": 2 } }
  }
}
```

### Authentication

#### Webhook User

Webhooks can be sent as a specific user (useful for audit trails):

1. Create or edit an endpoint
2. Set **Webhook User** to a Redmine user
3. Save

**Benefit:** All webhook requests will show as that user in Redmine logs.

#### HTTPS & API Keys

**Requirements:**
- Webhook URLs must use **HTTPS** with valid certificates
- Consider adding authentication (API keys, HMAC signatures)

**Implementation:**
```bash
# Add headers to webhook URL
https://hooks.slack.com/services/XXXXXX?api_key=YOUR_KEY
# OR use HMAC signature in payload
```

### Global Pause

Pause all webhook deliveries from Redmine settings:

1. Navigate to: **Administration > Plugins**
2. Find: **Redmine Webhook Plugin**
3. Click: **Configure**
4. Set **Pause webhook deliveries** to **Yes**
5. Save

**Effect:** No new deliveries will be created or sent. Existing pending deliveries will remain in queue.

### Advanced Settings

#### Retry Policy

The plugin uses exponential backoff for failed deliveries:

| Attempt | Wait Time |
|----------|------------|
| 1 | Immediate (0s) |
| 2 | 1 minute |
| 3 | 5 minutes |
| 4 | 25 minutes |
| 5+ | 2 hours (max) |

After 5 failed attempts, the delivery is marked as **Dead**.

#### Retention Settings

Configure automatic cleanup of old deliveries:

1. Navigate to: **Administration > Plugins > Redmine Webhook Plugin**
2. Set **Retention Period** (default: 30 days)
3. Save

**Note:** This applies to successful and failed deliveries.

---

## Usage Guide

### Monitoring Webhook Deliveries

View all webhook deliveries in: **Administration > Webhook Deliveries**

#### Columns

| Column | Description |
|---------|-------------|
| **Endpoint** | Which endpoint received the delivery |
| **Event** | Event type (issue/time_entry) + action |
| **Resource** | Issue ID or Time Entry ID |
| **Status** | Pending, Success, Failed, Dead |
| **Scheduled At** | When delivery was queued |
| **Attempt Count** | Number of retry attempts |
| **Last Attempt** | Timestamp of last HTTP request |

#### Filtering

Use the filters at the top to find specific deliveries:

- **By Endpoint:** Select from dropdown
- **By Status:** Pending, Success, Failed, Dead
- **By Date Range:** Start and end dates
- **By Resource ID:** Search specific issue/time entry

#### Viewing Delivery Details

1. Click on a delivery row
2. View detailed information:
   - **Request Headers**
   - **Request Body** (payload)
   - **Response Status Code**
   - **Response Body**
   - **Error Message** (if applicable)

### Replaying Failed Deliveries

Retry failed or dead deliveries:

**Single Replay:**
1. Click on a Failed delivery
2. Click the **Replay** button
3. Confirm

**Bulk Replay:**
1. Filter to Failed or Dead deliveries
2. Check the boxes for deliveries to replay
3. Click **Replay Selected**

**Note:** Replay creates new delivery records; original records are preserved.

### Exporting to CSV

Export delivery logs for analysis:

1. Apply your desired filters
2. Click **Export to CSV**
3. Download the file

**CSV Format:**
```csv
Endpoint,Event,Resource,Status,Scheduled At,Attempt Count,Last Attempt,Error
Production Slack,issue created,123,Success,2026-02-03 12:00:00,1,2026-02-03 12:00:00,
```

### Purging Old Deliveries

Clean up delivery logs:

1. Filter to old deliveries (e.g., older than 30 days)
2. Click **Purge**
3. Confirm

**Note:** This permanently deletes selected delivery records.

---

## Admin Interface

### Webhook Endpoints Page

**Location:** Administration > Webhook Endpoints

**Actions:**
- **Create** new endpoint
- **Edit** existing endpoint
- **Delete** endpoint (with confirmation)
- **View Deliveries** filtered by endpoint
- **Test** endpoint (sends test event)

**Endpoint Fields:**
```
┌─────────────────────────────────────────┐
│ Name: Production Slack                │
│ URL: https://hooks.slack.com/...   │
│ Events:                              │
│   ☑ Issue Created                   │
│   ☐ Issue Updated                   │
│   ☑ Time Entry Created               │
│ Payload Mode: Standard                  │
│ Webhook User: [Select user...]         │
│ Enabled: ☑                          │
└─────────────────────────────────────────┘
```

### Webhook Deliveries Page

**Location:** Administration > Webhook Deliveries

**Actions:**
- **Filter** deliveries
- **View** delivery details
- **Replay** failed/dead deliveries
- **Export** to CSV
- **Purge** old records

**Delivery Status Indicators:**
| Status | Color | Badge | Description |
|---------|--------|--------|-------------|
| **Pending** | Blue | Waiting to be sent |
| **Success** | Green | Delivered successfully |
| **Failed** | Orange | HTTP error, will retry |
| **Dead** | Red | All retries exhausted |

### Settings Page

**Location:** Administration > Plugins > Redmine Webhook Plugin (Configure)

**Options:**
- **Pause Webhook Deliveries:** Global pause toggle
- **Retention Period:** Days to keep deliveries
- **Logging Level:** (future) debug, info, warn

---

## Troubleshooting

### Common Issues

#### Issue: Webhook Not Triggering

**Possible Causes:**
1. Endpoint is disabled
2. Event type not configured for endpoint
3. Global pause is active
4. Redmine webhooks disabled in configuration

**Solutions:**
```bash
# 1. Check endpoint status
# Navigate to Administration > Webhook Endpoints
# Verify "Enabled" is checked

# 2. Check global pause
# Navigate to Administration > Plugins
# Verify "Pause webhook deliveries" is unchecked

# 3. Check Redmine config
# Look in config/configuration.yml
# Ensure: webhooks_enabled: true (if applicable)
```

#### Issue: Delivery Failed (HTTP 5xx)

**Possible Causes:**
1. External endpoint is down
2. SSL/TLS certificate error
3. Authentication failure
4. Rate limiting by external service

**Solutions:**
1. Check external endpoint status
2. Verify URL is correct and accessible
3. Check SSL certificate: `openssl s_client -connect hooks.slack.com:443`
4. Review external service logs

#### Issue: Delivery Stuck in Pending

**Possible Causes:**
1. `redmine:webhooks:process` cron job not running
2. Database locked
3. Global pause enabled

**Solutions:**
```bash
# 1. Check rake task is scheduled
crontab -l
# Should have: */5 * * * * cd /var/www/redmine && RAILS_ENV=production bundle exec rake redmine:webhooks:process

# 2. Run manually to test
cd /var/www/redmine
RAILS_ENV=production bundle exec rake redmine:webhooks:process

# 3. Check process queue
RAILS_ENV=production bundle exec rake redmine:webhooks:status
```

#### Issue: Native Webhooks Still Disabled (Redmine 7+)

**Symptom:** After uninstalling, Redmine's native webhooks menu is missing.

**Cause:** Web server not restarted after uninstallation.

**Solution:**
```bash
# Restart web server
systemctl restart puma
# OR
systemctl reload apache2

# Or reinstall and uninstall again
./installer/install.sh -d /var/www/redmine
./installer/uninstall.sh -d /var/www/redmine -R
```

### Debug Mode

Enable detailed logging:

1. Edit `config/additional_environment.rb`:
   ```ruby
   config.log_level = :debug
   ```

2. Restart Redmine

3. Check logs:
   ```bash
   tail -f /var/log/redmine/production.log | grep webhook
   ```

### Log Locations

| Environment | Log Path |
|-------------|------------|
| **Production** | `/var/log/redmine/production.log` |
| **Development** | `log/development.log` |
| **Test** | `log/test.log` |
| **Plugin Logs** | `/var/log/redmine/plugins/` (if configured) |

---

## Security

### HTTPS Requirements

**⚠️ Critical:** Webhook URLs must use HTTPS.

**Risks of HTTP:**
- Data transmitted in clear text
- Man-in-the-middle attacks
- No verification of endpoint authenticity

**Validation:**
```bash
# Test HTTPS endpoint
curl -v https://hooks.slack.com/services/XXXXXX

# Should show: SSL certificate verification
```

### Authentication Methods

#### 1. API Key in URL

```bash
https://hooks.example.com/webhook?api_key=YOUR_SECRET_KEY
```

**Pros:** Simple, easy to implement
**Cons:** Key exposed in logs, URL may be cached

#### 2. HMAC Signature

**Setup:**
1. Generate secret key: `openssl rand -hex 32`
2. Add to Redmine settings (custom field)
3. Plugin signs payload with HMAC-SHA256
4. External endpoint verifies signature

**Payload with Signature:**
```json
{
  "event_id": "uuid",
  "event_type": "issue",
  "action": "created",
  "timestamp": 1706971200,
  "signature": "a1b2c3d...",
  "data": { ... }
}
```

**External Verification:**
```python
import hmac
secret = "your_secret_key"
signature = hmac.new(data, secret, hashlib.sha256).hexdigest()
if signature == payload['signature']:
    # Valid
```

#### 3. OAuth 2.0 Bearer Token

```bash
curl -X POST https://hooks.example.com/webhook \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d @payload.json
```

### IP Whitelisting

If your external service requires IP whitelisting:

**Find Redmine Server IP:**
```bash
# Check outbound IP
curl ifconfig.me
# OR check with your network team
```

**Configure Whitelist:**
- Add Redmine server IP to external service allowlist
- Allow outbound HTTPS (port 443)

### Rate Limiting

Protect your endpoint from spam/duplicate events:

```ruby
# External endpoint example (Ruby/Sinatra)
before '/webhook' do
  rate_limit = RateLimiter.new(100, 1.minute) # 100 req/min
  unless rate_limit.allowed?(request.ip)
    status 429
    body "Too Many Requests"
  end
end
```

---

## Advanced Configuration

### Batch Processing

Control the number of deliveries processed per rake task:

```bash
# Process 100 deliveries per batch
RAILS_ENV=production BATCH_SIZE=100 bundle exec rake redmine:webhooks:process

# Process default (50)
RAILS_ENV=production bundle exec rake redmine:webhooks:process
```

**Use Case:** Control resource usage on busy Redmine instances.

### Custom Retention

Configure retention per endpoint:

1. Edit endpoint configuration
2. Add custom retention period (in future release)
3. Save

**Note:** Retention applies to both successful and failed deliveries.

### Event Filtering Logic

#### By Project

Only send webhooks for specific projects:

```ruby
# Custom filter implementation (future feature)
webhook.events = {
  project_ids: [1, 2, 3], # Only these projects
  exclude_project_ids: [99] # Exclude this project
}
```

#### By User

Only send webhooks for specific users:

```ruby
webhook.events = {
  user_ids: [1, 5, 10], # Only these users
  exclude_user_ids: [2], # Exclude admin users
}
```

#### By Tracker/Priority

Filter based on issue attributes:

```ruby
webhook.events = {
  tracker_ids: [1, 2], # Bug, Feature
  priority_ids: [4, 5] # High, Urgent
}
```

---

## API Reference

### Event Payload Structure

All webhook payloads follow this structure:

```json
{
  "event_id": "string (UUID)",
  "event_type": "issue|time_entry",
  "action": "created|updated|deleted",
  "occurred_at": "ISO 8601 datetime",
  "redmine_url": "string (URL)",
  "actor": {
    "id": "integer",
    "login": "string",
    "name": "string",
    "email": "string"
  },
  "resource": {
    // Issue or TimeEntry object based on event_type
  },
  "changes": {
    // For 'updated' actions only
    "field_name": {
      "old": "previous value",
      "new": "new value"
    }
  }
}
```

### Issue Payload (Standard Mode)

```json
{
  "event_id": "123e4567-e89b-12d3-a456-426614174000",
  "event_type": "issue",
  "action": "created",
  "occurred_at": "2026-02-03T12:00:00Z",
  "redmine_url": "https://redmine.example.com/issues/123",
  "actor": {
    "id": 1,
    "login": "admin",
    "name": "Administrator",
    "email": "admin@example.com"
  },
  "issue": {
    "id": 123,
    "subject": "Bug fix needed",
    "description": "Fix authentication in login flow",
    "status": {
      "id": 1,
      "name": "New"
    },
    "priority": {
      "id": 4,
      "name": "High"
    },
    "tracker": {
      "id": 1,
      "name": "Bug"
    },
    "assigned_to": {
      "id": 2,
      "login": "developer",
      "name": "Developer"
    },
    "author": {
      "id": 1,
      "login": "admin",
      "name": "Administrator"
    },
    "project": {
      "id": 5,
      "name": "Main Project",
      "identifier": "main-project"
    },
    "category": {
      "id": 1,
      "name": "Development"
    },
    "fixed_version": null,
    "start_date": "2026-02-03",
    "due_date": "2026-02-10",
    "estimated_hours": 8.0,
    "spent_hours": 0.0,
    "done_ratio": 0,
    "is_private": false,
    "created_on": "2026-02-03T12:00:00Z",
    "updated_on": "2026-02-03T12:00:00Z",
    "closed_on": null,
    "last_note": "Initial issue creation",
    "custom_fields": [
      {
        "id": 1,
        "name": "Severity",
        "value": "Critical"
      }
    ]
  }
}
```

### Time Entry Payload (Standard Mode)

```json
{
  "event_id": "456e7890-f12c-34d5-b678-532610428100",
  "event_type": "time_entry",
  "action": "created",
  "occurred_at": "2026-02-03T12:00:00Z",
  "redmine_url": "https://redmine.example.com/time_entries/45",
  "actor": {
    "id": 2,
    "login": "developer",
    "name": "Developer"
  },
  "time_entry": {
    "id": 45,
    "project": {
      "id": 5,
      "name": "Main Project"
    },
    "issue": {
      "id": 123,
      "subject": "Bug fix needed"
    },
    "user": {
      "id": 2,
      "login": "developer",
      "name": "Developer"
    },
    "activity": {
      "id": 9,
      "name": "Development"
    },
    "hours": 2.5,
    "comments": "Fixed the authentication bug",
    "spent_on": "2026-02-03",
    "created_on": "2026-02-03T12:00:00Z",
    "updated_on": "2026-02-03T12:00:00Z",
    "custom_fields": []
  }
}
```

### Changes Payload (For Updated Actions)

```json
{
  "changes": {
    "status": {
      "old": {
        "id": 1,
        "name": "New"
      },
      "new": {
        "id": 2,
        "name": "In Progress"
      }
    },
    "assigned_to": {
      "old": null,
      "new": {
        "id": 2,
        "login": "developer"
      }
    },
    "estimated_hours": {
      "old": "5.0",
      "new": "8.0"
    },
    "custom_fields": {
      "1": {
        "old": "Low",
        "new": "Critical"
      }
    }
  }
}
```

### Response Status Codes

| Code | Meaning | Plugin Action |
|-------|-----------|--------------|
| **200-299** | Success | Delivery marked "Success" |
| **400-499** | Client Error | Retry with backoff |
| **500-599** | Server Error | Retry with backoff |
| **429** | Rate Limited | Retry after delay |

---

## Migration & Upgrades

### Version Compatibility

| Plugin Version | Redmine | Notes |
|---------------|----------|--------|
| 1.0.x | 5.1.0+ | Current release |

### Upgrading from v0.x

If upgrading from v0.x or earlier:

1. **Backup Redmine:**
   ```bash
   tar -czf redmine-backup-$(date +%Y%m%d).tar.gz /var/www/redmine
   ```

2. **Uninstall Old Plugin:**
   ```bash
   cd /path/to/old/redmine_webhook_plugin
   ./installer/uninstall.sh -d /var/www/redmine
   ```

3. **Install New Plugin:**
   ```bash
   cd /path/to/new/redmine_webhook_plugin
   ./installer/install.sh -d /var/www/redmine -R
   ```

4. **Run Migrations:**
   ```bash
   cd /var/www/redmine
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
   ```

5. **Verify Configuration:**
   - Check webhook endpoints still exist
   - Test webhooks are triggering
   - Review delivery logs

### Database Changes

**Migration v1.0.0:**
- Creates `webhook_endpoints` table
- Creates `webhook_deliveries` table
- Adds indexes for performance

**Schema:**
```sql
-- webhook_endpoints
CREATE TABLE webhook_endpoints (
  id INTEGER PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  url TEXT NOT NULL,
  events_config TEXT NOT NULL,
  payload_mode VARCHAR(20) DEFAULT 'minimal',
  enabled BOOLEAN DEFAULT 1,
  webhook_user_id INTEGER,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

-- webhook_deliveries
CREATE TABLE webhook_deliveries (
  id INTEGER PRIMARY KEY,
  endpoint_id INTEGER NOT NULL,
  event_id VARCHAR(255) NOT NULL UNIQUE,
  event_type VARCHAR(20) NOT NULL,
  action VARCHAR(20) NOT NULL,
  resource_type VARCHAR(50) NOT NULL,
  resource_id INTEGER NOT NULL,
  status VARCHAR(20) NOT NULL,
  scheduled_at DATETIME NOT NULL,
  attempt_count INTEGER DEFAULT 0,
  last_attempt_at DATETIME,
  response_status INTEGER,
  response_body TEXT,
  error_message TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);
```

### Backward Compatibility

**Breaking Changes in v1.0.0:**
- None from v0.x to v1.0.0

**Deprecation Warnings:**
- None

---

## Changelog

### v1.0.0-RC1 (2026-02-03)

**Added:**
- Admin navigation menu for Webhook Deliveries
- Global delivery pause functionality
- Configurable batch processing (`BATCH_SIZE` env var)
- Payload field alignment (`journal` → `last_note`)
- Production-ready installer scripts
- Automatic native webhook handling (disable/enable)

**Fixed:**
- CI pipeline for tag-based releases
- Test compatibility across Redmine versions

**Documentation:**
- Comprehensive wiki documentation
- Installation and uninstaller guides
- Troubleshooting section
- API reference

### v0.5.x (Previous)

- Initial webhook functionality
- Basic endpoint configuration
- Delivery tracking UI

---

## Support & Resources

### Getting Help

- **Issues:** https://git.example.com/your-org/redmine_webhook_plugin/-/issues
- **Documentation:** https://git.example.com/your-org/redmine_webhook_plugin
- **AGENTS.md:** Developer guide

### Additional Resources

- [Redmine Documentation](https://www.redmine.org/projects/redmine/wiki)
- [Plugin API Reference](https://www.redmine.org/projects/redmine/wiki/PluginApi)
- [Webhook Best Practices](https://sendgrid.com/blog/webhook-security-best-practices)

### Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on contributing to this plugin.

---

## License

This plugin is licensed under the same terms as Redmine. See [LICENSE](../LICENSE) for details.

---

**Last Updated:** 2026-02-03
**Plugin Version:** 1.0.0-RC1
**Maintainer:** Redmine Webhook Plugin Contributors
