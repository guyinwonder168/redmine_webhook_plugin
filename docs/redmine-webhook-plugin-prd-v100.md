# Product Requirements Document (PRD): Redmine Webhook Plugin (v1.0.0)

| Field | Value |
| --- | --- |
| Product | Outbound Webhooks Plugin for Redmine |
| Target Redmine | **>= 5.1.0** (tested through **7.0.x**) |
| Document date | 2025-12-29 |
| Source design | [design/v1-redmine-webhook-plugin-design.md](design/v1-redmine-webhook-plugin-design.md) |

**Redmine 7.0+ compatibility:** Native webhooks exist in trunk. When native webhooks are present, the plugin remains authoritative and disables or bypasses native delivery to avoid duplicates.

[[_TOC_]]

## 1) Background / Problem

Redmine installations often need to integrate with external systems (CI/CD, chat/notifications, data pipelines, audit systems, service desks). Redmine’s built-in mechanisms are not sufficient for real-time, configurable, reliable outbound event delivery across all change paths (UI, REST API, bulk edits).

This plugin provides outbound HTTP webhooks for key Redmine objects with delivery reliability, change diffs, and admin-level configuration.

## 2) Goals

- Provide **reliable outbound webhooks** for Redmine events with a **clear, stable JSON schema**.
- Support **multiple endpoints**, configured **globally by admins**.
- Support per-endpoint:
  - event/action toggles
  - project allowlist
  - payload mode (minimal vs full)
  - retry policy
- For updates, include **before/after** values with **both raw and display text**.
- Authenticate outbound requests by sending `X-Redmine-API-Key` for a selected “webhook user”, and **handle API key rotation** automatically.

## 3) Non-goals (v1)

- Wiki webhooks.
- Per-project webhook configuration UI.
- Custom headers beyond `X-Redmine-API-Key` (may be added later).
- Signature/HMAC-based auth (may be added later).
- Per-endpoint tracker filtering (all Issue trackers are included).
- Delivery statistics dashboard (metrics visible via delivery log filters only).
- Endpoint health checks (periodic connectivity pings).
- Event batching (one HTTP request per event).
- Audit log for endpoint configuration changes.
- Immediate retry button (use bulk replay instead).
- Endpoint tagging/grouping.
- API access to delivery logs (CSV export only in v1).

## 4) Users / Personas

- **Redmine Administrator**
  - Configures endpoints, selects webhook user, manages retry and retention.
  - Needs visibility into failures and the ability to replay deliveries.
- **Integration Developer / Receiver Owner**
  - Consumes webhook payloads, uses minimal/full mode, reconciles updates using before/after diffs.

## 5) Scope (v1)

### In scope

- **Issue events** for all trackers (Bug/Bugfix/Task/Epic/ChangeRequest/etc are tracker values on `Issue`)
  - Actions: create, update, delete (configurable per endpoint)
- **Time entry events**
  - Actions: create, update, delete (configurable per endpoint)

### Deferred

- Wiki events.

## 6) Functional Requirements

### 6.1 Endpoint management (Admin-only)

- **FR-1:** Provide an admin UI to list webhook endpoints.
- **FR-2:** Admin can create an endpoint with:
  - `name`, `url`, `enabled`
  - `webhook_user` (a Redmine user)
  - `payload_mode`: `minimal` or `full`
  - enabled events/actions (issue/time_entry × create/update/delete)
  - project allowlist (empty = all projects)
  - retry policy (attempts, backoff, retryable statuses)
  - request options (timeout, SSL verification)
  - bulk_replay_rate_limit (deliveries per minute; default: 100)
  - url must be valid HTTP or HTTPS format (validated on save)
  - endpoint names must be unique (validation error on duplicate); URLs may be duplicated
- **FR-3:** Admin can edit and disable/enable an endpoint. ✅ **IMPLEMENTED** (Tasks 8 & 10, Verified 2025-12-29)
    - Edit action: Implemented in Task 8
    - Toggle enable/disable: Implemented in Task 10 with `@endpoint.toggle!(:enabled)`
    - Tests: `test_toggle_flips_enabled_flag` and `test_toggle_can_enable_disabled_endpoint`
    - Verified on: Redmine 5.1.0, 5.1.10, 6.1.0
- **FR-3a:** Endpoint configuration change impact:
   - `payload_mode` change: applies to NEW events only; pending deliveries use mode from creation time
   - `project_allowlist` change: filtering applied at event capture time; pending deliveries are not re-filtered
   - `enabled` toggle: takes effect immediately for all pending/failed deliveries
   - `url` change: NEW deliveries use new URL; pending deliveries use original URL (per FR-7)
   - `retry_policy` change: per FR-22a (new attempts only)
- **FR-4:** Admin can delete an endpoint. ✅ **IMPLEMENTED** (Task 9, Verified 2025-12-29)
    - Confirmation required: "Delete endpoint 'X'? This will soft-delete N associated deliveries."
    - Soft-deleted deliveries marked with status 'endpoint_deleted' (FR-20b)
    - Implementation: `app/controllers/admin/webhook_endpoints_controller.rb` (destroy action)
    - Tests: `test/functional/admin/webhook_endpoints_controller_test.rb` (test_destroy_deletes_endpoint_and_marks_deliveries)
    - Verified on: Redmine 5.1.0, 5.1.10, 6.1.0
- **FR-5:** Admin can "send test" to an endpoint (synthetic payload; recorded as a delivery). ✅ **IMPLEMENTED** (Task 11, Verified 2025-12-29)
     - Implementation: Test action creates delivery with is_test=true flag
     - Payload uses synthetic data: event_type='test', action='test', payload = { message: "Test delivery" }
     - Payload mode respects endpoint's configured payload_mode (minimal or full)
     - Test deliveries include `"is_test": true` in envelope and delivery record
     - Tests: `test_test_action_creates_a_test_delivery` and `test_test_action_requires_admin`
     - Verified on: Redmine 5.1.0, 5.1.10, 6.1.0
   - **FR-5a:** Test delivery indicator:
     - Deliveries created via "send test" (FR-5) include flag: is_test=true
     - Delivery log UI shows test deliveries with visual indicator (badge/icon)
   - **FR-5b:** Test failure handling:
     - Failed test attempts show warning/notification but do not block endpoint save

### 6.2 Event capture & dispatch

- **FR-6:** Webhooks must fire for events originating from UI and REST API (and other commit paths), not only controller actions.
  - **FR-6b:** Event ordering (soft FIFO):
    - Processing order:
      - DB runner mode: SELECT ... ORDER BY resource_type, resource_id, sequence_number (natural ordering, no distributed locks)
      - ActiveJob mode: ~~Deliveries for same resource queued with 500ms stagger delay (delivery N+1 scheduled 500ms after N)~~ **DEFERRED to v1.1** — v1.0 uses immediate enqueueing; receivers should use `occurred_at` for ordering
    - Payload includes 'occurred_at' (ISO8601 UTC) and 'sequence_number'
    - RECEIVER GUIDANCE: Implement 'occurred_at' comparison as defensive measure for rare out-of-order edge cases (retries, network issues)
    - This provides ~95%+ ordering correctness without complex distributed locking
    - Strict FIFO guarantee deferred to v1.1 if monitoring shows need
    - Sequence number assignment:
      - Value: Unix epoch microseconds at event creation time (e.g., 1735052425123456)
      - Implementation: `(Time.now.to_f * 1_000_000).to_i`
      - Guarantees: 100% unique (microsecond precision), 100% sortable (higher = later)
      - No database locking required
      - Database column type: BIGINT (required for microsecond precision values)
- **FR-7:** For each matching endpoint, persist a delivery record containing:
   - `payload`: immutable JSON snapshot (serialized at event time)
   - `endpoint_url`: URL at delivery creation time (immutable; endpoint URL changes do not affect existing deliveries)
   - `retry_policy_snapshot`: copy of endpoint's retry policy at creation time (for audit; replay uses current policy per FR-22a)
   - `webhook_user_id`: reference to user for API key lookup
   - Metadata: event_id, resource_type, resource_id, sequence_number, created_at, scheduled_at
- **FR-8:** Endpoint matching must support:
  - endpoint enabled
  - event/action enabled
  - project allowlist (empty = all projects; otherwise project must be included)
  - tracker filtering is **not** part of v1 (all trackers included)

### 6.3 Payload schema (minimal vs full)

- **FR-9:** All payloads are JSON and contain a stable envelope:
   - `event_id` (UUID), `event_type` (`issue` | `time_entry`), `action` (`created` | `updated` | `deleted`), `occurred_at` (ISO8601 UTC timestamp), `sequence_number` (integer; per-resource ordering hint)
   - `delivery_mode` (`minimal` | `full`)
   - `schema_version` (string, e.g., "1.0") - payload structure version; receivers should handle unknown versions gracefully

   - `project` (when available): `{ id, identifier, name }`
   - `actor` (when available): `{ id, login, name }`
     - For user-initiated events: the authenticated user
     - For REST API events: the API key owner
     - For system/automated events (e.g., scheduled tasks): null
- **FR-10:** Issue payload always includes tracker info:
  - `issue.tracker`: `{ id, name }`
- **FR-9a:** Time entry payload includes issue reference:
  - `time_entry.issue`: `{ id, subject }` (minimal mode)
  - `time_entry.issue`: `{ id, subject, tracker, project }` (full mode)
  - If time entry is not associated with an issue: issue = null
- **FR-11:** For **update** events, payload must include a `changes[]` array where each entry includes **both raw and display text**:
   - `field`, `kind` (`attribute` | `custom_field`)
   - `old: { raw, text }`, `new: { raw, text }`
   - **FR-11a:** Change tracking scope for Issues:
     - Tracked in changes[] array: Core attributes (subject, description, status_id, priority_id, assigned_to_id, category_id, fixed_version_id, start_date, due_date, done_ratio, estimated_hours, parent_issue_id) and Custom field values (all custom fields configured for the tracker)
     - NOT tracked in v1 (deferred): Journal notes/comments (available in full mode as 'last_note' field, but not in changes[]), Attachments added/removed, Watchers added/removed, Issue relations (blocks, related to, etc.), Workflow metadata
   - **FR-11b:** Change tracking scope for Time Entries:
     - Tracked in changes[] array: Core attributes (hours, spent_on, activity_id, comments, user_id) and Custom field values (if time entry custom fields enabled)
      - NOT tracked in v1: N/A (time entries have minimal associations)
   - **FR-11c:** Empty changes handling:
     - If update event has no tracked field changes (e.g., only notes added), changes[] is empty array
     - Event still fires (useful for receivers tracking notes via last_note in full mode)

- **FR-12:** Minimal mode includes IDs and URLs sufficient for the receiver to fetch more details:
  - Issue events: `issue.id`, `issue.url` (web), `issue.api_url` (REST)
  - Time entry events: `time_entry.id`, `time_entry.url` (web), `time_entry.api_url` (REST)
- **FR-13:** Full mode includes a current snapshot of relevant fields (core fields + custom fields where applicable).
  - Snapshot represents the resource state AFTER the change is applied; previous state is available via changes[] old values.
- **FR-14:** Delete events must include a snapshot persisted at event time, since later fetch may be impossible.

### 6.4 Authentication: webhook user API key

- **FR-15:** Outgoing requests include `X-Redmine-API-Key` for the endpoint’s selected webhook user.
- **FR-15a:** Outbound request format:
   - Method: `POST`
   - `Content-Type: application/json; charset=utf-8`
   - `User-Agent: RedmineWebhook/<plugin_version> (Redmine/<redmine_version>)`
   - `X-Redmine-API-Key: <webhook_user_api_key>`
   - `X-Redmine-Event-ID: <event_id>` (for receiver-side idempotency)
- **FR-16:** The plugin stores `webhook_user_id` only (must not store the raw API key).
- **FR-17:** On delivery attempt, if the selected user has no API key, the plugin **auto-generates** one using Redmine’s API key mechanism (when allowed by Redmine configuration).
- **FR-18:** Monitor API key rotation without storing the raw key by recording a **fingerprint** (e.g., `sha256(api_key)`) used for each delivery (or “missing”).
- **FR-19:** Admin UI surfaces auth health states:
   - user inactive/locked
   - API key missing/unavailable
   - repeated auth failures (401/403)
   - API key rotated (when fingerprint changes between deliveries)
- **FR-19a:** Webhook user validation on endpoint save:
   - Admin UI must validate webhook_user_id exists and is active
   - Warning if user has no API key (will be auto-generated on first delivery)
   - Error if user is locked/inactive (cannot save endpoint with invalid user)
- **FR-19b:** Webhook user validation at delivery time:
   - Before HTTP attempt, verify webhook_user exists and is active
   - If user deleted/locked: mark delivery as 'failed' with error code 'webhook_user_invalid' (do not attempt HTTP request)
   - If user active but no API key:
     - Attempt auto-generation (FR-17)
     - If auto-gen not permitted by Redmine config: mark delivery as 'failed' with error 'api_key_unavailable'
- **FR-19c:** API key fingerprint calculation:
   - On each delivery attempt, fetch current API key from user's Token table
   - Calculate sha256(api_key) and store in delivery record as 'api_key_fingerprint'
   - If fingerprint changes between deliveries to same endpoint, admin UI surfaces "API key rotated" indicator
    - If Token lookup fails, store fingerprint as 'missing'
- **FR-19d:** Webhook user deletion impact on endpoints:
   - When a Redmine user is deleted:
     - Endpoints using that user as webhook_user are auto-disabled
     - Endpoint status shows error: "Webhook user deleted"
     - Pending/failed deliveries for that endpoint remain paused
     - Admin notification sent (via Redmine's built-in notification if available, or surfaced in plugin dashboard)
   - Re-enabling requires selecting a new valid webhook_user


### 6.5 Delivery, retries, and replay

- **FR-20:** Persist each delivery with status lifecycle: `pending` → `delivering` → (`success` | `failed` | `dead`).
    - **FR-20a:** Delivery lifecycle state transitions:
      - pending → delivering: when picked up by worker/runner
      - delivering → success: on HTTP 2xx response
      - delivering → failed: on retryable error (not max attempts yet)
      - delivering → dead: on non-retryable error OR max attempts exhausted
      - delivering → pending: on stale lock recovery (locked_at > 5 minutes old; handled by DB runner claiming logic, FR-28b)
      - failed → delivering: on retry attempt
      - failed/dead → pending: on manual replay (FR-24)
    - **FR-20b:** Endpoint state impact on deliveries:
      - Disabled endpoint: pending/failed deliveries are paused (not attempted)
      - Re-enabled endpoint: paused deliveries resume processing
      - Deleted endpoint: all associated deliveries are soft-deleted (preserved for audit) with status marked as `endpoint_deleted`
    - **FR-20c:** Replay eligibility:
      - failed deliveries: can be replayed (resets to pending)
      - dead deliveries: can be replayed (resets to pending)
      - endpoint_deleted deliveries: CANNOT be replayed (endpoint no longer exists; preserved as read-only audit records)
- **FR-21:** HTTP response handling:
   - Success: any HTTP 2xx response
   - Redirects (3xx): follow up to 5 redirects; final response determines success/failure; reject HTTPS→HTTP downgrade (security); store final URL in delivery metadata
   - Client errors (4xx except retryable): non-retryable failure
   - Server errors (5xx): retryable per FR-22
- **FR-22:** Retry policy must be configurable per endpoint:
  - max attempts
  - exponential backoff parameters (base/max delay)
  - retryable HTTP statuses (typical: 408, 429, 5xx; configurable)
  - timeouts and SSL verification
  - Default retry policy (applied if not configured):
    - max_attempts: 5
    - base_delay: 60 seconds
    - max_delay: 3600 seconds (1 hour)
    - retryable_statuses: [408, 429, 500, 502, 503, 504]
    - timeout: 30 seconds
    - ssl_verify: true
  - Network errors (connection refused, timeout, DNS failure) are retryable
  - SSL/TLS validation errors:
    - if ssl_verify=true: mark delivery failed (non-retryable) and surface warning
    - if ssl_verify=false: allow delivery but show informational notice that SSL verification is disabled
- **FR-22a:** Retry policy change behavior:
  - Retry policy changes (max_attempts, backoff, retryable_statuses) apply ONLY to new delivery attempts
  - Existing failed/dead deliveries retain the retry policy from their original creation until manually replayed (FR-24)
  - Manual replay resets delivery to 'pending' and applies the CURRENT retry policy of the endpoint
- **FR-22b:** Global retry pause (optional for v1):
  - Admin can set global flag 'deliveries_paused=true' to temporarily halt all delivery attempts
  - Paused deliveries remain in pending/failed state
  - Useful for maintenance windows or receiver outages
- **FR-22c:** Retry scheduling:
  - On delivery creation: scheduled_at = NULL (immediate)
  - On retryable failure: scheduled_at = NOW() + backoff_delay
  - Backoff formula: min(base_delay * 2^attempt, max_delay)
- **FR-23:** Provide delivery log UI with filters:
  - endpoint, project, event type/action, status, date/time
   - Pagination: 50 deliveries per page (configurable in plugin settings)
   - Sort: newest first by default; sortable by any column
   - Each delivery has stable URL: `/admin/webhooks/deliveries/:id` (shareable for debugging)
   - Timestamps displayed in admin's browser timezone; hover tooltip shows UTC value
   - Delivery record displays: attempt_count (current/max), next_retry_at (for failed status)
   - CSV export: admin can export filtered delivery log to CSV file
     - Columns: delivery_id, event_id, endpoint_name, event_type, action, resource_id, status, attempt_count, http_status, error_code, created_at, delivered_at
  - **FR-23a:** Delivery log search and filter:
      - Existing filters: endpoint, project, event type, action, status,
        date/time range
      - Additional filters:
        - Search by event_id (exact match)
        - Search by delivery_id (exact match)
        - Search by resource_id (issue_id or time_entry_id)
        - Filter by HTTP status code range (2xx, 4xx, 5xx, or specific code)
         - Filter by is_test flag
       - Default view: all deliveries shown (including test)
       - Test deliveries excluded from success rate metrics (Section 9)


  - **FR-23b:** Delivery error codes (shown in delivery logs and API):
      - webhook_user_invalid: webhook user deleted or locked
      - api_key_unavailable: cannot obtain API key
      - payload_too_large: payload exceeds limits after truncation
      - connection_timeout: HTTP request timed out
      - connection_refused: target refused connection
      - dns_error: could not resolve hostname
      - ssl_error: SSL/TLS handshake failed
      - http_error: non-retryable HTTP status received
- **FR-24:** Admin can replay a delivery (re-queue and attempt again) from the UI.
- **FR-24a:** Bulk replay:
   - Admin can select multiple deliveries by filter criteria and replay all
   - Confirmation required: "Replay N deliveries to endpoint X?"
   - Rate limiting: configurable per-endpoint (default: 100 deliveries per minute)
   - Bulk replay resets all selected to 'pending' and applies CURRENT endpoint retry policy
- **FR-25:** Provide retention/purge policy:
  - manual purge
  - optional scheduled purge of old delivery records
- **FR-25a:** Scheduled purge configuration:
  - retention_days_success: 7 (default)
  - retention_days_failed_dead: 7 (default)
   - purge_statuses: ['success', 'failed', 'dead', 'endpoint_deleted']


  - Purge runs as rake task or background job

### 6.6 Execution modes (async + fallback)

- **FR-26:** Primary delivery execution uses `ActiveJob` (async where available).
- **FR-27:** Provide a DB-backed runner (rake task) that can deliver "due" deliveries from the database for environments without a reliable background job runner.
- **FR-28:** The DB runner must avoid double-sending (use locking or claim semantics).
- **FR-28a:** Execution mode selection:
  - Plugin detects ActiveJob availability at runtime
  - ActiveJob is "available" if gem is loaded AND queue adapter is configured (ActiveJob::Base.queue_adapter set)
  - If ActiveJob configured but worker not running, deliveries will queue (admin responsible for monitoring queue depth)
  - If ActiveJob unavailable or uncertain: use db_runner mode (safer default for new installations)
  - Admin can override via plugin setting: 'delivery_executor: auto | activejob | db_runner'
- **FR-28b:** DB runner delivery claiming:
  - Rake task selects deliveries where:
    - status IN ('pending', 'failed')
    - scheduled_at <= NOW() (or NULL for immediate)
    - locked_at IS NULL OR locked_at < NOW() - 5 minutes (stale lock recovery)
  - Atomic update: SET status='delivering', locked_at=NOW(), locked_by=<runner_id> WHERE id=X AND locked_at IS NULL
  - runner_id format: "<hostname>:<pid>:<timestamp>" (e.g. "redmine-01:12345:20251223120000")
  - After HTTP attempt: SET status='success/failed', locked_at=NULL
- **FR-28c:** Double-delivery prevention:
  - Both ActiveJob and DB runner honor the same status lifecycle
  - Database-level locking via 'locked_at' + 'locked_by' columns
  - ActiveJob jobs check delivery status before HTTP attempt (skip if already success/delivering with recent lock)

## 7) Non-functional Requirements

- **NFR-1 (Compatibility):** Must run on Redmine **>= 5.1.0** (tested through **7.0.x**).
- **NFR-2 (Performance):** Webhook creation should not materially slow down user actions; delivery should be async where possible.
   - Recommended maximum: 50 endpoints per installation (not enforced; admin responsibility to monitor performance)
   - Each event creates one delivery per matching endpoint (N endpoints = N deliveries per event)
- **NFR-3 (Reliability):** Persist deliveries and provide retry/replay; tolerate temporary receiver outages.
- **NFR-4 (Security):**
  - Do not store raw API keys.
  - Respect SSL verification by default.
  - Protect Admin UI via Redmine admin permissions.
  - **NFR-4a:** Security assumptions (v1):
    - All webhook receiver endpoints are considered FULLY TRUSTED with complete
      visibility into Redmine project data
    - HTTPS is STRONGLY RECOMMENDED for all endpoint URLs to protect API keys
      in transit
    - HTTP URLs are permitted but will trigger a security warning in the admin UI
    - No field-level redaction or data sensitivity controls are provided in v1
    - Delivery logs contain immutable payload snapshots that persist according
      to retention policy (FR-25); admins must manually purge to remove
      sensitive data
    - All Redmine administrators have full access to all delivery logs (no
      project-scoped access control)
    - Security recommendation for admins:
      - Only configure webhook endpoints for receivers you fully trust
      - Use HTTPS URLs exclusively
      - Implement regular retention purges for projects with sensitive data
- **NFR-5 (Observability):** Provide enough delivery metadata for operational debugging without storing excessive sensitive response data (store only an excerpt).
  - **NFR-5a:** Delivery record observability:
    - Response body excerpt: first 2KB (configurable)
    - Request headers: store User-Agent, Content-Type, Content-Length
    - Response headers: store all headers (typically small)
    - Timing: record `duration_ms` (milliseconds from request start to response complete)
- **NFR-6 (Transactional consistency):** Webhook delivery records must only persist AFTER successful commit of the triggering Redmine operation. Implementation must use ActiveRecord after_commit callbacks (not after_save) to ensure delivery creation happens post-transaction. If Redmine operation rolls back, no webhook delivery should be created.
- **NFR-7 (Bulk operation handling):**
  - Webhook deliveries from bulk operations are created individually (one delivery record per affected resource)
  - Deliveries are queued for processing with normal priority
  - To prevent system overload during bulk operations:
    - ActiveJob mode: Respect queue adapter's concurrency limits (e.g., Sidekiq concurrency setting). Recommended: max 10 concurrent webhook delivery workers.
    - DB runner mode: Process max 50 deliveries per rake execution (configurable via BATCH_SIZE env var)
  - Receivers experiencing high volume should implement rate limiting (429) which triggers retry backoff (FR-22)
- **NFR-8 (Payload size limits):**
  - Threshold (1MB) applies to entire serialized JSON payload
  - If payload exceeds 1MB, apply truncation in this order:
    1. Truncate changes[] to most recent 100 entries (not first 100)
    2. If still exceeds, exclude custom fields from full mode snapshot (minimal mode IDs only)
    3. If still exceeds, mark delivery 'failed' with error 'payload_too_large'
  - Truncated payloads include flags:
    - "changes_truncated": true, "changes_kept": "most_recent_100", "changes_total_count": <N>
    - "custom_fields_excluded": true (if step 2 applied)
  - Database column for delivery.payload uses MEDIUMTEXT (16MB limit)

## 8) Compatibility verification (CI)

Compatibility is enforced via a GitLab CI version matrix that runs against **prebaked Redmine images** (offline runner friendly). At minimum, the matrix must include:

- Redmine **5.1.0** (minimum supported)
- Redmine **5.1.10** (representative 5.1 line image)
- Redmine **6.1.x** (current stable line image)
- Redmine **7.0.x** (trunk/dev version)

## 9) Success Metrics (examples)

- Delivery success rate (`success / total`) over 7 and 30 days.
- Median time-to-delivery for async mode.
- Number of endpoints actively configured.
- Mean time to detect and resolve auth issues (401/403) using delivery logs.

## 10) Risks / Edge Cases

- Journals may not capture every possible change format equally across Redmine versions; payload builder must handle missing/unknown fields safely.
- Some installations may disable REST API or restrict API keys; auto-generation must handle "not allowed" gracefully and surface a clear admin warning.
- Receivers may rate-limit (429); retry strategy must be configurable and safe.
- Delete events require careful snapshotting at moment of deletion.
- **Circular webhooks:** If Redmine instance A and B have webhooks to each other, infinite loops are possible. Receivers must implement their own loop detection (e.g., track event_id, ignore if already processed).
- **Clock skew:** All occurred_at timestamps are UTC ISO8601. Receivers in different timezones should normalize to UTC for comparison.
- **Deleted projects:** Deliveries for deleted projects contain a stale project snapshot. Receivers attempting REST API fetch will get 404; use payload snapshot as source of truth.
- **Payload schema evolution:** If plugin version changes payload schema, replayed deliveries use the schema version from original event time (immutable snapshot). Receivers must handle schema variations gracefully.
- **Redmine core compatibility:** Plugin is tested against Redmine 5.1.0 through 7.0.x. Journal format changes in future Redmine versions may affect change tracking; plugin will handle unknown fields by omitting them from changes[] (safe degradation).
- **Endpoint URL changes:** When admin updates an endpoint's URL, existing pending/failed deliveries continue using the ORIGINAL URL from delivery creation time (immutable snapshot). Only newly created deliveries use the updated URL.
- **Out-of-order delivery edge cases:** While the plugin implements soft FIFO ordering (FR-6b), receivers syncing to external databases should implement 'occurred_at' timestamp comparison to discard stale events in rare out-of-order scenarios (network retries, worker failures).
- **Deleted projects in allowlist:** When a project is deleted from Redmine, it is automatically removed from all endpoint project_allowlists. If an allowlist becomes empty after removal, the endpoint matches all projects (per FR-8 empty = all). Admin should review endpoint configuration after project deletion.

## 10.1) Known Limitations (v1)

- **Filtering:** v1 supports only project allowlist and event/action toggles.
  Fine-grained filtering (priority, status, assignee, tracker-specific) is
  not available. Receivers should implement their own filtering based on
  payload data.
- **Ordering:** Strict FIFO ordering is not guaranteed (soft FIFO ~95%+ correctness). Receivers should implement timestamp-based conflict resolution using the 'occurred_at' field. ActiveJob stagger delay (FR-6b) is deferred to v1.1.
- **Duplicate delivery edge case:** If a worker holds a delivery lock beyond the 5-minute stale threshold (e.g., extremely slow network), the delivery may be processed twice. Receivers MUST implement idempotency using `event_id` to safely handle rare duplicates.

## 11) Acceptance Criteria (v1)

- Admin can create and enable multiple endpoints globally.
- Endpoint can be restricted to a project allowlist (empty means all projects).
- Issue create/update/delete emits deliveries with tracker info; updates include `changes[]` with `{raw, text}` for old/new values.
- Time entry create/update/delete emits deliveries; updates include `changes[]` with `{raw, text}`.
- Requests include `X-Redmine-API-Key` for the selected webhook user; plugin auto-generates the key if missing (when permitted).
- Delivery log shows status, attempts, last HTTP status/error, and supports replay.
- Retries follow the configured policy and do not double-send from the DB runner.

## 12) Future Enhancements

- Add optional extra headers (e.g., `X-Redmine-Event-Type`, `X-Redmine-Event-Action`).
- Wiki events.
- Per-endpoint issue priority allowlist/blocklist.
- Per-endpoint issue status allowlist/blocklist.
- Per-endpoint tracker allowlist (currently all trackers included).
- Per-endpoint assignee/author allowlist.
- Per-endpoint custom headers/body templates.
- Signature/HMAC or other receiver verification mechanisms.

## 13) References

- [Redmine hooks](https://www.redmine.org/projects/redmine/wiki/hooks)
