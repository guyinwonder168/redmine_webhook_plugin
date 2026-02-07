# Redmine Webhook Plugin — Admin UI Wireframes (v1)

| Field | Value |
| --- | --- |
| Source PRD | [../redmine-webhook-plugin-prd-v100.md](../redmine-webhook-plugin-prd-v100.md) |
| Target Redmine | **>= 5.1.1** (tested through **6.1.x**) |
| PRD version | v1.0.0 (2025-12-24) |

[[_TOC_]]

These wireframes target **Admin-only** pages for:

- Endpoint management (CRUD + send test)
- Delivery log (filter + replay + bulk replay + CSV export)
- Retention/purge (manual + optional scheduled)

Terminology:

- **Endpoint** = configured webhook destination + policy.
- **Delivery** = one persisted attempt record for (event × endpoint) with immutable payload snapshot.

## Redmine 7.0+ Compatibility

On Redmine 7.0+, native webhooks exist but are disabled when this plugin is active. The Admin UI stays in the plugin (Administration -> Webhooks) as the source of truth.

---

## Global navigation

Entry point:

- **Administration → Webhooks** (plugin page)

Tabs:

```
Administration > Webhooks
[ Endpoints ] [ Deliveries ] [ Settings ]
```

---

## Page: Endpoints (index)

Purpose: list endpoints, quick status, quick actions.

```
Administration > Webhooks
[ Endpoints ] [ Deliveries ] [ Settings ]

+ New endpoint

Endpoints
-----------------------------------------------------------------------------------------------------------------
| Enabled | Name        | URL                         | Mode    | Webhook user | Projects | Auth   | Actions |
|--------:|-------------|-----------------------------|---------|--------------|----------|--------|---------|
|   [x]   | CI notify   | https://.../webhooks        | minimal | svc_webhook  | All      | OK     | Edit ▾  |
|   [ ]   | Slack       | https://.../redmine         | full    | bot_slack    | 3 proj   | WARN   | Edit ▾  |
|   [!]   | Legacy      | http://.../old              | minimal | api_user     | All      | HTTP!  | Edit ▾  |
-----------------------------------------------------------------------------------------------------------------

Row "Actions" dropdown:
- Edit
- Enable / Disable
- Send test…
- Delete…
```

Auth badge states (per FR-19):

- `OK` — API key present + user active + no recent auth failures
- `WARN` — API key missing/unavailable or user locked/inactive
- `AUTH FAIL` — recent 401/403 failures
- `ROTATED` — API key fingerprint changed since last delivery
- `HTTP!` — non-HTTPS URL configured (security warning per NFR-4a)

---

## Page: Endpoint (new/edit)

Purpose: configure an endpoint (filters, auth user, retries, request options).

```
Administration > Webhooks > Endpoint: (New | Edit)
[ Endpoints ] [ Deliveries ] [ Settings ]

[ Save ] [ Cancel ]                           [ Send test… ] (edit mode only)

Basics
  Name:         [_________________________]   (unique, required)
  Enabled:      [x]
  URL:          [_______________________________________________]
                ⚠ Security warning: HTTPS strongly recommended (shown if http://)
  Webhook user: [ dropdown of users ____________________________ ]
                ⚠ Warning: User has no API key (will be auto-generated)
                ✗ Error: User is locked/inactive (cannot save)
  Payload mode: (•) minimal   ( ) full

Request options
  Timeout (sec):  [ 30 ]
  SSL verify:     [x]   (verify ON by default)
                  ⚠ Notice: SSL verification disabled (shown if unchecked)

Events / actions
  (toggle matrix)
                Create   Update   Delete
    Issue        [x]      [x]      [x]
    Time entry   [x]      [x]      [x]

Projects (allowlist)
  (•) All projects
  ( ) Only selected projects:
      [ multi-select / pick list of projects ___________________ ]
      Hint: empty allowlist == all projects

Retry policy
  Max attempts:        [ 5 ]
  Backoff base (sec):  [ 60 ]
  Backoff max (sec):   [ 3600 ]
  Retryable statuses:  [x] 408  [x] 429  [x] 500  [x] 502  [x] 503  [x] 504  [+ add]
  Retry 401/403:       [ ] (default off)

Bulk replay
  Rate limit (deliveries/min): [ 100 ]

Auth health (read-only, edit mode only)
  User status:       Active | Locked | Inactive
  API key:           Present | Missing | Not allowed
  Last fingerprint:  3f2a… (sha256 prefix) | missing
  Fingerprint status: Unchanged | Rotated (since last delivery)
  Recent auth failures: 0 | 3 (last 24h)
```

Validation notes (per FR-2, FR-19a):

- Name must be unique (validation error on duplicate: "Endpoint name already exists")
- URL must be valid HTTP or HTTPS format (validation error on invalid)
- Webhook user must exist and be active (error if locked/inactive prevents save)
- Warning if user has no API key (informational, does not block save)

---

## Modal: Delete endpoint confirmation (per FR-4)

```
Delete endpoint?

Are you sure you want to delete endpoint "CI notify"?

This will soft-delete 247 associated deliveries.
(Deliveries will be preserved for audit but marked as 'endpoint_deleted')

[ Delete ] [ Cancel ]
```

---

## Modal: Send test (per FR-5)

Purpose: create a synthetic delivery and attempt it, recorded like a real delivery.

```
Send test

  Event type:   [ issue ▼ ]
  Action:       [ updated ▼ ]
  Mode:         [ inherit endpoint (minimal) ]

  Note: Test payload will include "is_test": true in envelope.
        Test deliveries are visible in delivery log with 🧪 indicator.

[ Send test ] [ Cancel ]
```

After send:

```
Test delivery created

  Status: success | failed
  HTTP status: 200 | 500
  Duration: 150ms

  [ View delivery ] [ Close ]
```

Failed test warning (per FR-5b):

```
⚠ Test delivery failed

  Error: connection_timeout
  HTTP status: -

  This does not prevent endpoint save.

  [ View delivery ] [ Close ]
```

---

## Page: Deliveries (index)

Purpose: operational visibility + replay + filtering + bulk actions + CSV export.

```
Administration > Webhooks
[ Endpoints ] [ Deliveries ] [ Settings ]

Filters
  Endpoint:    [ All ▼ ]    Project: [ All ▼ ]    Type: [ All ▼ ]    Action: [ All ▼ ]
  Status:      [ All ▼ ]    HTTP status: [ All ▼ | 2xx | 4xx | 5xx | specific code ]
  Test only:   [ ] Show test deliveries only
  From: [____-__-__ __:__]   To: [____-__-__ __:__]
  Event ID:    [________________]    Delivery ID: [________________]
  Resource ID: [________________]
  [ Apply ] [ Clear ]

Actions
  [ Bulk replay… ] [ Export CSV ]

Retention / purge
  Purge deliveries older than: [ 30 ] days   [ Purge… ]
  (Scheduled purge: configured via rake/cron — see documentation)

Showing 1-50 of 1,247 deliveries                              [ ◀ ] Page 1 of 25 [ ▶ ]

Deliveries
---------------------------------------------------------------------------------------------------------------
| 🧪 | Occurred at*       | Endpoint   | Project | Type      | Action  | Status     | Att | Next retry   | HTTP | Actions |
|----|-------------------|------------|---------|-----------|---------|------------|-----|--------------|------|---------|
|    | 2025-12-19 10:12  | CI notify  | core    | issue     | created | success    | 1/5 | -            | 204  | View ▾  |
|    | 2025-12-19 10:11  | Slack      | core    | issue     | updated | failed     | 3/5 | 10:20        | 500  | View ▾  |
|    | 2025-12-19 10:10  | Slack      | core    | time_entry| created | delivering | 2/5 | -            | -    | View ▾  |
| 🧪 | 2025-12-19 10:05  | CI notify  | -       | issue     | updated | success    | 1/5 | -            | 200  | View ▾  |
|    | 2025-12-19 09:55  | CI notify  | core    | issue     | deleted | dead       | 5/5 | -            | 404  | View ▾  |
---------------------------------------------------------------------------------------------------------------

* Timestamps shown in your browser timezone. Hover for UTC.

Row "Actions" dropdown:
- View
- Replay… (enabled for failed/dead; disabled for endpoint_deleted)
```

Legend:

- 🧪 = Test delivery (per FR-5a)
- Att = attempts (current/max)
- Status column values: `pending`, `delivering`, `success`, `failed`, `dead`, `endpoint_deleted`

---

## Modal: Bulk replay (per FR-24a)

```
Bulk replay deliveries?

You are about to replay 47 deliveries matching your filter criteria.

  Endpoint: Slack
  Status: failed
  Date range: 2025-12-18 to 2025-12-19

Rate limit: 100 deliveries per minute (configured on endpoint)

All selected deliveries will be reset to 'pending' and use the
endpoint's CURRENT retry policy.

[ Replay 47 deliveries ] [ Cancel ]
```

---

## Modal: CSV export (per FR-23)

```
Export deliveries to CSV

Export 1,247 deliveries matching your current filter?

Columns included:
  delivery_id, event_id, endpoint_name, event_type, action,
  resource_id, status, attempt_count, http_status, error_code,
  created_at, delivered_at

[ Export ] [ Cancel ]
```

---

## Page: Delivery (detail)

Purpose: debug a single delivery; allow replay.

```
Administration > Webhooks > Delivery #12345
[ Endpoints ] [ Deliveries ] [ Settings ]

[ Replay… ] [ Back to list ]

Summary
  Delivery ID:    12345
  Event ID:       550e8400-e29b-41d4-a716-446655440000
  Sequence:       1735052425123456
  Status:         failed
  Endpoint:       Slack
  Endpoint URL:   https://hooks.slack.com/...  (URL at delivery creation)
  Event:          issue.updated
  Resource:       Issue #42
  Occurred at:    2025-12-19 10:11:03 UTC
  Schema version: 1.0
  Is test:        No | Yes 🧪

Retry status
  Attempts:       3 / 5
  Next attempt:   2025-12-19 10:20:00 UTC
  Retry policy:   max=5, base=60s, max_delay=3600s (snapshot at creation)

Last attempt
  HTTP status:    500
  Error code:     http_error
  Error message:  Internal Server Error
  Duration:       1200ms
  Auth fingerprint: 3f2a… | missing
  Final URL:      https://hooks.slack.com/... (after redirects)

Request headers (sent)
  Content-Type:   application/json; charset=utf-8
  User-Agent:     RedmineWebhook/1.0.0 (Redmine/6.1.0)
  Content-Length: 2048

Response headers (received)
  Content-Type:   text/html
  X-Request-Id:   abc123

Response excerpt (first 2KB)
  [ ... truncated ... ]

Attempt history
  - 10:11:04  status=500  duration=900ms   error=http_error
  - 10:12:10  timeout     duration=10000ms error=connection_timeout
  - 10:14:20  status=500  duration=1100ms  error=http_error

Payload (immutable snapshot)
  [ JSON viewer / preformatted block ]   [ Copy to clipboard ]
```

Payload truncation indicators (per NFR-8):

```
⚠ Payload was truncated due to size limits:
  - changes_truncated: true (kept most recent 100 of 250 changes)
  - custom_fields_excluded: true
```

---

## Modal: Replay confirmation (per FR-24)

```
Replay delivery?

This will reset the delivery to 'pending' and enqueue a new attempt
using the endpoint's CURRENT retry policy.

  Delivery ID: 12345
  Event: issue.updated
  Original attempts: 3

[ Replay ] [ Cancel ]
```

---

## Page: Settings (plugin configuration)

Purpose: global plugin settings.

```
Administration > Webhooks
[ Endpoints ] [ Deliveries ] [ Settings ]

[ Save ]

Execution mode (per FR-28a)
  Delivery executor: ( ) Auto-detect   (•) ActiveJob   ( ) DB runner
  Note: Auto-detect will use ActiveJob if available, otherwise DB runner.

Pagination
  Deliveries per page: [ 50 ]

Observability (per NFR-5a)
  Response excerpt size (KB): [ 2 ]

Global controls (optional, per FR-22b)
  [ ] Pause all deliveries (maintenance mode)
  Note: When enabled, no deliveries will be attempted. Pending/failed
        deliveries will remain paused until unchecked.

Retention defaults (per FR-25a)
  Success retention (days):      [ 7 ]
  Failed/dead retention (days):  [ 7 ]
```

---

## Error states and edge cases

### Endpoint with deleted webhook user (per FR-19d)

```
Endpoints
-----------------------------------------------------------------------------------------------------------------
| Enabled | Name        | URL                         | Mode    | Webhook user  | Projects | Auth        | Actions |
|--------:|-------------|-----------------------------|---------|---------------|----------|-------------|---------|
|   ⛔    | Legacy API  | https://.../webhooks        | minimal | [DELETED]     | All      | USER DELETE | Edit ▾  |
-----------------------------------------------------------------------------------------------------------------

Note: Endpoint is auto-disabled. Select a new webhook user to re-enable.
```

### Delivery with endpoint deleted (per FR-20b, FR-20c)

```
Administration > Webhooks > Delivery #99999

Summary
  Status:    endpoint_deleted
  Endpoint:  [DELETED] (was: CI notify)

⚠ This delivery cannot be replayed because the endpoint no longer exists.
   Preserved for audit purposes only.

[ Back to list ]
```

---

## UI notes / constraints (implementation-friendly)

- Keep pages under **Admin** permission checks only.
- Prefer Redmine standard admin layout + tables; avoid heavy JS dependencies.
- All actions that enqueue work should create/update **Delivery** records so operators can see what happened.
- Do not display or store the raw API key; always redact request headers in logs/preview.
- Timestamps displayed in admin's browser timezone; hover/tooltip shows UTC value.
- Stable URLs for deliveries: `/admin/webhooks/deliveries/:id` (shareable for debugging).
- Test deliveries marked with 🧪 indicator and excluded from success rate metrics.
- HTTP URLs trigger security warning banner (strongly recommend HTTPS).
- Bulk replay respects per-endpoint rate limits to prevent overwhelming receivers.
