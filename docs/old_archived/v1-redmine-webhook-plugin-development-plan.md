# Redmine Webhook Plugin — Development Plan (v1)

| Field | Value |
| --- | --- |
| Scope | v1 as defined in [../redmine-webhook-plugin-prd-v100.md](../redmine-webhook-plugin-prd-v100.md) |
| Design | [../design/v1-redmine-webhook-plugin-design.md](../design/v1-redmine-webhook-plugin-design.md) |
| Admin UI wireframes | [../UIUX/v1-redmine-webhook-plugin-wireframes.md](../UIUX/v1-redmine-webhook-plugin-wireframes.md) |
| Target Redmine | **>= 5.1.1** (tested through **6.1.x**) |
| PRD version | v1.0.0 (2025-12-24) |

[[_TOC_]]

This plan is structured as **vertical slices**: each slice is end-to-end, demoable, and suitable for a small MR.

---

## Principles

- **Ship end-to-end slices** (capture → persist delivery → attempt → admin visibility).
- **Model-level hooks** (not controller-only) so events fire for UI + REST API + bulk edits.
- **Immutable payload snapshots** stored with each delivery (including `endpoint_url` at creation time).
- **No secrets at rest:** never store raw API keys; store only fingerprints.
- **Transactional consistency:** use `after_commit` callbacks (not `after_save`) to ensure deliveries persist only after successful Redmine operation commit (NFR-6).
- **Compatibility-first:** prefer stdlib + Redmine primitives; avoid version-sensitive internals where possible.

---

## Slice 1 — DB Schema + Endpoint CRUD

**Why:** establishes data model foundation and basic admin UI; no delivery logic yet.

**PRD coverage:** FR-1..4, FR-7 (schema only), FR-19a (validation)

### Deliverables

- **DB tables + migrations**
  - `webhook_endpoints`
    - `id` (primary key)
    - `name` (string, unique constraint, validated, not null)
    - `url` (string, HTTP/HTTPS format validated on save, not null)
    - `enabled` (boolean, default: true)
    - `webhook_user_id` (fk to users, not null)
    - `payload_mode` (string/enum: 'minimal'|'full', default: 'minimal')
    - `bulk_replay_rate_limit` (integer, default: 100)
    - `timeout_seconds` (integer, default: 30)
    - `ssl_verify` (boolean, default: true)
    - Retry policy fields:
      - `max_attempts` (integer, default: 5)
      - `backoff_base_seconds` (integer, default: 60)
      - `backoff_max_seconds` (integer, default: 3600)
      - `retryable_statuses` (string/array, default: '408,429,500,502,503,504')
    - Event toggles (booleans, all default: false):
      - `issue_create_enabled`
      - `issue_update_enabled`
      - `issue_delete_enabled`
      - `time_entry_create_enabled`
      - `time_entry_update_enabled`
      - `time_entry_delete_enabled`
    - `created_at`, `updated_at` (timestamps)
  - `webhook_endpoint_projects` (project allowlist join table)
    - `id` (primary key)
    - `webhook_endpoint_id` (fk, not null)
    - `project_id` (fk, not null)
    - Unique index on `(webhook_endpoint_id, project_id)`
  - `webhook_deliveries`
    - `id` (primary key)
    - `webhook_endpoint_id` (fk, not null, indexed)
    - `event_id` (UUID, not null, indexed)
    - `event_type` (string: 'issue'|'time_entry', not null)
    - `action` (string: 'created'|'updated'|'deleted', not null)
    - `occurred_at` (datetime, not null)
    - `sequence_number` (BIGINT, Unix epoch microseconds, not null)
    - `payload` (MEDIUMTEXT, 16MB limit, immutable JSON snapshot, not null)
    - `endpoint_url` (string, immutable copy of URL at delivery creation time, not null)
    - `retry_policy_snapshot` (text/JSON, copy of endpoint's retry policy at creation)
    - `webhook_user_id` (fk, not null)
    - `project_id` (fk, nullable — cached for filtering/indexing)
    - `resource_type` (string: 'Issue'|'TimeEntry', not null)
    - `resource_id` (integer, not null)
    - `status` (string/enum: 'pending'|'delivering'|'success'|'failed'|'dead'|'endpoint_deleted', default: 'pending')
    - `attempts_count` (integer, default: 0)
    - `scheduled_at` (datetime, nullable — when to attempt next)
    - `next_attempt_at` (datetime, nullable — computed from backoff)
    - `locked_at` (datetime, nullable)
    - `locked_by` (string, nullable — runner_id format per FR-28b)
    - `last_http_status` (integer, nullable)
    - `last_error` (text, nullable)
    - `error_code` (string, nullable — per FR-23b)
    - `response_excerpt` (text, 2KB cap, nullable)
    - `duration_ms` (integer, nullable)
    - `api_key_fingerprint` (string, nullable — sha256 or 'missing')
    - `is_test` (boolean, default: false)
    - `created_at`, `updated_at` (timestamps)
  - **Indexes:**
    - `webhook_deliveries`: `(status, scheduled_at)`, `(status, next_attempt_at)`, `(webhook_endpoint_id, occurred_at)`, `(project_id, occurred_at)`, `(resource_type, resource_id, sequence_number)`, `(event_id)`
    - `webhook_endpoints`: `(webhook_user_id)`

- **Admin UI (Admin-only)**
  - Endpoints list page: name, url (truncated), enabled toggle, payload_mode, webhook_user, project count, actions dropdown
  - Endpoint create/edit form:
    - All fields from schema
    - Event toggles as checkbox matrix
    - Project allowlist multi-select
  - Validations per FR-2, FR-19a:
    - Unique endpoint name (validation error on duplicate)
    - Valid HTTP/HTTPS URL format (validation error on invalid)
    - Webhook user exists and is active (error if locked/inactive)
    - Warning if selected user has no API key (informational)
  - HTTP URL security warning: display when non-HTTPS URL configured (NFR-4a)
  - Delete confirmation per FR-4: "Delete endpoint 'X'? This will soft-delete N associated deliveries."

### Acceptance checks

- Create/edit/delete endpoints via Admin UI.
- Validation errors shown for duplicate name, invalid URL, locked user.
- HTTP URL shows security warning.
- Delete shows confirmation with delivery count.

---

## Slice 2 — Dumb Sink (dev/testing tool)

**Why:** enables testing delivery logic before implementing it; validates HTTP client behavior.

**PRD coverage:** (tooling, not PRD-specified)

### Deliverables

Add `tools/webhook_sink/` as a **dev/testing** receiver.

- **HTTP + HTTPS**
  - HTTP mode (default): `http://localhost:<port>/webhooks`
  - HTTPS mode: self-signed cert; support `ssl_verify` testing.
  - Auto-generate cert/key if not provided; persist under `tools/webhook_sink/certs/`.
- **Scenario-based responses** (easy failure simulation)
  - `success` → configurable `2xx`
  - `fail` → configurable non-2xx (e.g., `500`)
  - `auth_fail` → `401` or `403`
  - `rate_limit` → `429` + configurable `Retry-After`
  - `no_response` → sleep long enough to trigger client timeout
  - `drop` → accept socket then close without a response
  - `invalid_response` → write garbage/partial HTTP and close
  - `redirect` → `302` to another path (for redirect testing)
  - `redirect_downgrade` → `302` from HTTPS to HTTP (should be rejected)
  - `random` → weighted choice per request (seedable) for chaos testing
- **Per-request override**
  - Override scenario via query params (e.g., `?scenario=fail&status=503`).
  - Always redact `X-Redmine-API-Key` in logs.
  - Optionally persist request bodies to `tools/webhook_sink/received/` (gitignored).
- **Docs**
  - `tools/webhook_sink/README.md` with copy/paste URLs for each scenario.

### Acceptance checks

- Sink starts on configurable port.
- Each scenario responds as documented.
- API key is redacted in logs.

---

## Slice 3 — Delivery Attempt Engine + Auth Provider

**Why:** core HTTP delivery logic; enables "Send test" and real event delivery.

**PRD coverage:** FR-5, FR-15..19d, FR-20..22c (baseline), FR-26, FR-28a..c (baseline), NFR-4..6

### Deliverables

- **HTTP client wrapper**
  - POST with JSON body
  - Headers per FR-15a: `Content-Type`, `User-Agent`, `X-Redmine-API-Key`, `X-Redmine-Event-ID`
  - Timeout from endpoint config
  - SSL verification from endpoint config
  - Redirect handling per FR-21: follow up to 5 redirects; reject HTTPS→HTTP downgrade; store final URL

- **Delivery attempt service**
  - Status lifecycle per FR-20a: `pending → delivering → success|failed|dead`
  - State transitions:
    - `pending → delivering`: picked up by worker
    - `delivering → success`: HTTP 2xx
    - `delivering → failed`: retryable error (not max attempts yet)
    - `delivering → dead`: non-retryable error OR max attempts exhausted
    - `delivering → pending`: stale lock recovery (locked_at > 5 min)
  - Persist: `attempts_count`, `last_http_status`, `last_error`, `error_code`, `response_excerpt` (2KB cap), `duration_ms`
  - Error codes per FR-23b: `webhook_user_invalid`, `api_key_unavailable`, `connection_timeout`, `connection_refused`, `dns_error`, `ssl_error`, `http_error`, `payload_too_large`

- **Auth provider**
  - Pre-attempt validation per FR-19b: verify user exists and is active.
  - If user deleted/locked: mark delivery `failed` with error_code `webhook_user_invalid` (no HTTP attempt).
  - Fetch user API key; if missing, try to auto-generate (when permitted per FR-17).
  - If auto-gen not permitted: mark delivery `failed` with error_code `api_key_unavailable`.
  - Persist fingerprint per FR-19c: `sha256(api_key)` or `"missing"`.

- **Webhook user deletion handling per FR-19d**
  - Hook into User model: when user deleted, auto-disable endpoints using that user.
  - Surface "Webhook user deleted" error in endpoint status.

- **"Send test" action per FR-5**
  - Creates `webhook_delivery` row with `is_test=true`
  - Test payload: `event_type='issue'`, `action='updated'`, synthetic data
  - Payload includes `"is_test": true` in envelope
  - Attempts delivery immediately
  - Failed test shows warning but does not block endpoint save (FR-5b)

- **Minimal deliveries list UI**
  - List: status, endpoint, occurred_at, last_http_status, last_error, attempts, is_test indicator (badge)
  - Pagination: 50 per page (configurable)
  - Stable URL per delivery: `/admin/webhooks/deliveries/:id`
  - Timestamps in browser timezone with UTC tooltip

### Acceptance checks

- "Send test" → delivery created → attempt made → success/failure recorded.
- `ssl_verify=true` fails against sink HTTPS self-signed; `ssl_verify=false` succeeds.
- Sink `scenario=fail` records failure; `scenario=no_response` records timeout.
- Test delivery shows 🧪 indicator.
- User deletion auto-disables affected endpoints.

---

## Slice 4 — Issue "created" (minimal payload, endpoint matching)

**Why:** first real event capture; validates end-to-end flow.

**PRD coverage:** FR-6, FR-6b, FR-8, FR-9..10, FR-12, FR-15a, NFR-6..8

### Deliverables

- **Event capture**
  - `Issue.after_create_commit` emits deliveries for matching endpoints (NFR-6: after_commit only).
  - Sequence number assignment per FR-6b: `(Time.now.to_f * 1_000_000).to_i`.

- **Endpoint matching service**
  - Check: `enabled` AND `issue_create_enabled`
  - Check: project allowlist (empty = all; otherwise project.id in allowlist)
  - Create one delivery per matching endpoint

- **Payload builder (minimal)**
  - Envelope per FR-9: `event_id`, `event_type`, `action`, `occurred_at`, `sequence_number`, `schema_version("1.0")`, `delivery_mode`, `project`, `actor`
  - Actor per FR-9: `{ id, login, name }` for user-initiated; `null` for system/automated.
  - `issue`: `{ id, tracker: { id, name }, subject, url, api_url }`

- **Payload size check per NFR-8**
  - 1MB threshold with truncation rules (minimal payloads unlikely to hit this).

- **Bulk operation handling per NFR-7**
  - Individual deliveries per issue
  - Respect concurrency limits

- **Tests**
  - Endpoint matching logic
  - Payload schema presence
  - Sequence number ordering

### Acceptance checks

- Create issue (UI or REST) → deliveries created for matching endpoints.
- Payload includes all required envelope fields.
- Non-matching endpoints (wrong project, toggle off) receive no delivery.

---

## Slice 5 — Issue "updated" (Journal-based changes[] + full snapshot)

**PRD coverage:** FR-11, FR-11a..c, FR-13, risks/edge cases around journaling

### Deliverables

- **Event capture**
  - `Journal.after_create_commit` where `journalized_type == "Issue"`.
  - Match endpoints with `issue_update_enabled`.

- **changes[] builder per FR-11a**
  - Derive from `JournalDetail`: `{ field, kind, old:{raw,text}, new:{raw,text} }`
  - Tracked fields: core attributes (subject, description, status_id, priority_id, assigned_to_id, category_id, fixed_version_id, start_date, due_date, done_ratio, estimated_hours, parent_issue_id) + custom field values.
  - NOT tracked (v1): journal notes, attachments, watchers, issue relations, workflow metadata.
  - Unknown fields: omit from changes[] (safe degradation).

- **Empty changes handling per FR-11c**
  - If no tracked field changes (e.g., notes-only), `changes[]` is empty array.
  - Event still fires (receiver can access notes via `last_note` in full mode).

- **Full mode payload**
  - Include `issue_full` snapshot (core fields + custom fields, state AFTER change).
  - Include `last_note` for journal notes access.

- **Tests**
  - Journal detail → changes[] mapping
  - Custom field display formatting
  - Notes-only update → empty changes[]

### Acceptance checks

- Update issue status/assignee/custom field → webhook includes correct raw+text diffs.
- Notes-only update → webhook fires with empty `changes[]` array.
- Full mode includes complete issue snapshot.

---

## Slice 6 — Issue "deleted" (snapshot-at-delete)

**PRD coverage:** FR-14

### Deliverables

- **Event capture**
  - `Issue.after_destroy_commit`
  - Match endpoints with `issue_delete_enabled`.

- **Delete payload**
  - Capture full snapshot in-memory BEFORE destroy (using `before_destroy` to cache).
  - Payload built from cached snapshot; does not depend on future DB fetch.

- **Tests**
  - Delete event produces delivery with expected fields including full snapshot.

### Acceptance checks

- Delete issue → webhook includes full snapshot of deleted issue.
- Payload contains all fields that were present before deletion.

---

## Slice 7 — TimeEntry create/update/delete

**PRD coverage:** FR-6, FR-9, FR-9a, FR-11..13, FR-11b

### Deliverables

- **Event capture**
  - `TimeEntry.after_create_commit` (match `time_entry_create_enabled`)
  - `TimeEntry.after_update_commit` (match `time_entry_update_enabled`)
  - `TimeEntry.after_destroy_commit` (match `time_entry_delete_enabled`)

- **Time entry issue reference per FR-9a**
  - Minimal mode: `time_entry.issue`: `{ id, subject }` (or `null` if not associated).
  - Full mode: `time_entry.issue`: `{ id, subject, tracker, project }` (or `null`).

- **Update diffs per FR-11b**
  - Normalize `previous_changes` to `changes[]` with `{raw,text}`.
  - Tracked fields: hours, spent_on, activity_id, comments, user_id, custom fields.

- **Payload structure**
  - Minimal: `time_entry` with id, url, api_url, issue reference
  - Full: `time_entry_full` with all fields

- **Delete handling**
  - Same pattern as Issue delete: cache before destroy, build payload from cache.

- **Tests**
  - Create/update/delete events
  - Diff normalization
  - Issue reference inclusion (with and without associated issue)

### Acceptance checks

- Create/update/delete time entry → webhooks fire with correct payloads.
- Time entry with issue → issue reference included.
- Time entry without issue → issue is null.

---

## Slice 8 — Retries + Replay + DB-backed runner

**PRD coverage:** FR-20..28c, FR-22a..c, FR-24

### Deliverables

- **Retry scheduling per FR-22c**
  - On retryable failure: `next_attempt_at = NOW() + min(base_delay * 2^attempt, max_delay)`
  - Retryable: network errors, timeouts, configured HTTP statuses (default: 408,429,5xx)
  - Non-retryable: 401/403 (by default), SSL errors (if ssl_verify=true), other 4xx

- **Retry policy change behavior per FR-22a**
  - Policy changes apply ONLY to new delivery attempts.
  - Existing pending/failed deliveries use their `retry_policy_snapshot`.

- **DB runner per FR-28b**
  - Rake task: `redmine_webhook_plugin:deliver_due`
  - Select deliveries: `status IN ('pending', 'failed') AND (scheduled_at <= NOW() OR scheduled_at IS NULL) AND (locked_at IS NULL OR locked_at < NOW() - 5.minutes)`
  - Order by: `resource_type, resource_id, sequence_number` (soft FIFO per FR-6b)
  - Atomic claim: `UPDATE ... SET status='delivering', locked_at=NOW(), locked_by=<runner_id> WHERE id=X AND (locked_at IS NULL OR locked_at < stale_threshold)`
  - runner_id format: `<hostname>:<pid>:<timestamp>`
  - Batch size: 50 (configurable via BATCH_SIZE env var)

- **Concurrency safety per FR-28c**
  - Both ActiveJob and DB runner honor same status lifecycle.
  - Database-level locking via `locked_at` + `locked_by`.
  - ActiveJob jobs check delivery status before HTTP attempt (skip if already success/delivering with recent lock).

- **Single replay per FR-24**
  - Admin action on delivery detail page.
  - Resets to 'pending', clears attempts_count, applies CURRENT endpoint retry policy.
  - Only for `failed` or `dead` status (not `endpoint_deleted`).

- **Tests**
  - Backoff math correctness
  - Retryable vs non-retryable classification
  - Claim prevents double-send
  - Stale lock recovery

### Acceptance checks

- Failed delivery → scheduled for retry at correct backoff time.
- DB runner processes due deliveries without double-send.
- Replay action resets delivery and attempts again.

---

## Slice 9 — Bulk Replay + Rate Limiting

**PRD coverage:** FR-24a

### Deliverables

- **Bulk replay UI per FR-24a**
  - Admin can select deliveries by filter criteria (endpoint, status, date range).
  - Confirmation modal: "Replay N deliveries to endpoint X?"
  - All selected reset to 'pending', apply CURRENT endpoint retry policy.

- **Rate limiting**
  - Use per-endpoint `bulk_replay_rate_limit` (default: 100/minute).
  - Stagger `scheduled_at` across replayed deliveries to respect rate limit.

- **Tests**
  - Bulk selection and replay
  - Rate limit calculation and scheduling

### Acceptance checks

- Select 50 failed deliveries → bulk replay → all reset to pending with staggered schedules.
- Rate limit of 100/min → 50 deliveries scheduled over 30 seconds.

---

## Slice 10 — Delivery Log Enhancements + CSV Export

**PRD coverage:** FR-23, FR-23a..b, NFR-5a

### Deliverables

- **Enhanced filters per FR-23a**
  - Existing: endpoint, project, event type, action, status, date range
  - New filters:
    - Search by event_id (exact match)
    - Search by delivery_id (exact match)
    - Search by resource_id (issue_id or time_entry_id)
    - Filter by HTTP status code range (2xx, 4xx, 5xx, or specific code)
    - Filter by is_test flag
  - Default view: all deliveries (including test)

- **Delivery detail page enhancements**
  - Show all metadata: event_id, sequence_number, schema_version, endpoint_url (immutable)
  - Request headers sent: User-Agent, Content-Type, Content-Length
  - Response headers received (all)
  - Attempt history list
  - Payload viewer with copy button
  - Truncation indicators per NFR-8 (if applicable)

- **CSV export per FR-23**
  - Export filtered delivery log to CSV.
  - Columns: delivery_id, event_id, endpoint_name, event_type, action, resource_id, status, attempt_count, http_status, error_code, created_at, delivered_at

- **Observability per NFR-5a**
  - Response body excerpt: first 2KB (configurable in settings)
  - Timing: `duration_ms` recorded on each attempt

- **Tests**
  - Filter combinations
  - CSV export format

### Acceptance checks

- All filters work correctly.
- CSV export contains correct columns and data.
- Delivery detail shows complete metadata.

---

## Slice 11 — Auth Health + Retention/Purge

**PRD coverage:** FR-18..19, FR-25, FR-25a, NFR-5

### Deliverables

- **Auth health indicators per FR-19**
  - Endpoint list shows badge: OK, WARN, AUTH FAIL, ROTATED, HTTP!
  - Endpoint edit page shows read-only auth health section:
    - User status: Active | Locked | Inactive
    - API key: Present | Missing | Not allowed
    - Last fingerprint: prefix or "missing"
    - Fingerprint status: Unchanged | Rotated
    - Recent auth failures: count (last 24h)

- **Fingerprint rotation detection**
  - Compare fingerprint between deliveries to same endpoint.
  - Surface "API key rotated" if changed.

- **Retention/purge per FR-25, FR-25a**
  - Manual purge: Admin action with date threshold and confirmation.
  - Rake task: `redmine_webhook_plugin:purge_old_deliveries`
    - `retention_days_success`: 7 (default, configurable)
    - `retention_days_failed_dead`: 7 (default, configurable)
    - `purge_statuses`: ['success', 'failed', 'dead', 'endpoint_deleted']

- **Tests**
  - Auth health derivation logic
  - Purge deletes correct records

### Acceptance checks

- Auth badges display correctly based on user/key status.
- Manual purge deletes old deliveries.
- Rake purge respects retention settings.

---

## Slice 12 — Execution Mode Detection + Global Pause + Settings Page

**PRD coverage:** FR-26..28c, FR-22b

### Deliverables

- **Settings page (Admin UI)**
  - Delivery executor: Auto | ActiveJob | DB runner (per FR-28a)
  - Deliveries per page: configurable
  - Response excerpt size (KB): configurable
  - Global pause toggle (per FR-22b): pause all deliveries
  - Retention defaults: success days, failed/dead days

- **Execution mode detection per FR-28a**
  - Auto-detect ActiveJob availability (gem loaded + queue adapter configured).
  - If unavailable/uncertain: default to db_runner (safer).
  - Admin override via setting.

- **Global retry pause per FR-22b**
  - When enabled, no deliveries attempted.
  - Pending/failed remain paused until toggle disabled.
  - Visual indicator in Admin UI when paused.

- **ActiveJob stagger per FR-6b**
  - Deliveries for same resource queued with 500ms stagger delay.

- **Tests**
  - Execution mode detection
  - Global pause behavior
  - Settings persistence

### Acceptance checks

- Settings page saves/loads correctly.
- Global pause stops all delivery attempts.
- Execution mode respects setting.

---

## Compatibility checkpoints (do continuously)

- Run CI matrix (5.1.1 / 5.1.10 / 6.1) early after Slice 1 lands.
- Keep API-key generation and journaling handling behind small adapters so differences across Redmine versions are isolated.
- Ensure payloads remain stable (add schema tests for required keys).
- Test journal format changes across Redmine versions (safe degradation for unknown fields).

---

## Open questions resolved by PRD v1.0.0

1. **URL fields:** Payload includes both `url` (web) and `api_url` (REST) per FR-12.
2. **Journal notes-only updates:** Notes-only updates fire event with empty `changes[]`; notes accessible via `last_note` in full mode per FR-11c.
3. **Replay semantics:** Reset to pending, apply CURRENT endpoint retry policy per FR-22a and FR-24.
4. **Endpoint config changes:** payload_mode/project_allowlist apply to NEW events; pending deliveries use creation-time values per FR-3a.

---

## Risks / Edge Cases to address (from PRD Section 10)

- **Circular webhooks:** Receivers must implement their own loop detection (track event_id).
- **Clock skew:** All occurred_at timestamps are UTC ISO8601; receivers should normalize.
- **Deleted projects:** Deliveries contain stale snapshot; REST API fetch returns 404.
- **Payload schema evolution:** Replayed deliveries use original schema version (immutable).
- **Out-of-order delivery:** Receivers should compare `occurred_at` for rare edge cases.
- **Deleted projects in allowlist:** Auto-removed; empty allowlist matches all projects.
- **Duplicate delivery edge case:** If lock exceeds 5 min, may process twice; receivers MUST implement idempotency using `event_id`.

---

## Known Limitations (v1) — per PRD Section 10.1

- **Filtering:** Only project allowlist and event/action toggles; no priority/status/assignee/tracker filtering.
- **Ordering:** Soft FIFO (~95%+ correctness); receivers should use timestamp-based conflict resolution.
- **Duplicate delivery:** Rare edge case possible; receivers MUST implement idempotency.

---

## Slice Summary

| Slice | Focus | Key Deliverables |
|-------|-------|------------------|
| 1 | DB Schema + Endpoint CRUD | Tables, migrations, endpoint admin UI |
| 2 | Dumb Sink | Testing tool with scenario-based responses |
| 3 | Delivery Attempt Engine | HTTP client, auth provider, "Send test", minimal deliveries UI |
| 4 | Issue "created" | Event capture, endpoint matching, minimal payload |
| 5 | Issue "updated" | Journal-based changes[], full snapshot |
| 6 | Issue "deleted" | Snapshot-at-delete pattern |
| 7 | TimeEntry events | Create/update/delete for time entries |
| 8 | Retries + Replay | Backoff, DB runner, single replay |
| 9 | Bulk Replay | Multi-select replay with rate limiting |
| 10 | Delivery Log | Enhanced filters, CSV export, detail page |
| 11 | Auth Health + Purge | Health indicators, retention/purge |
| 12 | Settings + Global Pause | Execution mode, global controls |
