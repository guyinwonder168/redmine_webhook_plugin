# Redmine Webhook Plugin — Design (v1)

| Field | Value |
| --- | --- |
| Target Redmine | **>= 5.1.1** (tested through **6.1.x**) |
| PRD | [../redmine-webhook-plugin-prd-v100.md](../redmine-webhook-plugin-prd-v100.md) |
| Development plan | [../plans/v1-redmine-webhook-plugin-development-plan.md](../plans/v1-redmine-webhook-plugin-development-plan.md) |
| Admin UI wireframes | [../UIUX/v1-redmine-webhook-plugin-wireframes.md](../UIUX/v1-redmine-webhook-plugin-wireframes.md) |

[[_TOC_]]

## Goal

Build a Redmine plugin that emits outbound HTTP webhooks for **Issues (all trackers)** and **Time Entries**, compatible with **Redmine 5.1.1+** and tested through **Redmine 6.1.x**.

Key requirements:

- Multiple webhook endpoints.
- Global configuration only (Admin-level), no per-project UI.
- Per-endpoint project allowlist.
- Per-endpoint event/action toggles.
- Per-endpoint payload mode: **minimal** vs **full**.
- Updates must include **before/after** values (both **raw** and **display text**).
- Outgoing requests authenticate by sending `X-Redmine-API-Key` for a selected “webhook user”.
  - Auto-generate a user API key if missing.
  - Monitor API key rotation/invalid state without storing the raw key.
- Reliable delivery: retry policy per endpoint + persisted delivery log + replay + DB-backed runner.

## Non-goals (v1)

- Wiki webhooks (explicitly deferred).
- Per-project webhook configuration UI.
- Custom headers beyond `X-Redmine-API-Key` (can be added later).

## Compatibility targets

- Redmine 5.1.1+ and Redmine 6.1.x.
- Avoid dependencies that vary across versions; prefer stdlib `Net::HTTP`, ActiveRecord, and ActiveJob.

### Redmine 7.0+ Native Webhook Compatibility

Redmine trunk (future 7.0) introduces native webhook support via `class Webhook < ApplicationRecord`. Our plugin must handle this gracefully:

**Detection**: At runtime, check if native webhooks exist:
```ruby
def self.native_webhooks_available?
  defined?(::Webhook) && ::Webhook < ApplicationRecord
end
```

**Strategy**:
- **Redmine 5.1.x / 6.1.x** (no native): Full plugin functionality
- **Redmine 7.0+** (native exists): Plugin remains authoritative; detect native and disable/bypass native delivery to avoid duplicate events, while keeping plugin UI and delivery pipeline

**Native webhook capabilities** (as of trunk Dec 2024, disabled when plugin is active):
- Issue events (created/updated/deleted)
- Project-scoped webhooks with user permissions
- HMAC signature (`X-Redmine-Signature-256`)
- Background job delivery via `WebhookJob`

**Plugin enhancements over native** (potential v1+ features):
- TimeEntry webhooks (not in native)
- Delivery log with retry/replay UI
- Before/after change values with display text
- Minimal vs full payload modes

**Namespace**: All plugin code uses `RedmineWebhookPlugin::` namespace to avoid conflicts with native `Webhook` class.

## High-level architecture

1. **Event Capture**
   - Capture persisted domain events at the model level, so webhooks fire for UI + REST API + bulk changes.
2. **Event Dispatch**
   - For each matching endpoint, persist a delivery row with an immutable payload snapshot.
3. **Delivery Execution**
   - Attempt async delivery via `ActiveJob`.
   - Always support a DB-backed runner (rake task) for reliability.
4. **Admin UI**
   - CRUD endpoints.
   - Delivery log, filters, replay.
   - Retention/purge policy.

## Event capture strategy

### Issues

We treat “Bug/Bugfix/Task/Epic/ChangeRequest/etc” as **tracker values on the `Issue` model**. There is no separate “Bug model” in Redmine; it is still an `Issue`.

- **Create**: `Issue` `after_create_commit`
- **Delete**: `Issue` `after_destroy_commit`
- **Update**: prefer journaling:
  - Listen for `Journal` `after_create_commit` where `journalized_type == "Issue"`
  - Compute diffs using associated `JournalDetail` rows (`old_value` → `value`)
  - This is the most reliable “before/after” source for issue changes, including many custom field changes.

### Time entries

- **Create/Update/Delete**: `TimeEntry` `after_*_commit`
- Compute diffs from `previous_changes` (ActiveRecord change tracking), normalized to the same “changes array” format.

## Endpoint matching & filters

Each endpoint is considered for delivery when:

- endpoint is enabled
- the event type/action is enabled for that endpoint
- project allowlist matches
  - If allowlist is empty, it matches all projects.
  - If allowlist is non-empty, the project must be included.
- For v1: **no tracker filtering** (all trackers match).

## Payload schema

Payloads are JSON with a stable envelope plus object-specific content.

### Envelope (always present)

- `event_id`: UUID
- `event_type`: `"issue"` or `"time_entry"`
- `action`: `"created" | "updated" | "deleted"`
- `occurred_at`: ISO8601
- `project`: `{ id, identifier, name }` (when available)
- `actor`: `{ id, login, name }` (when available)
- `delivery_mode`: `"minimal" | "full"`

### Changes array for updates (required)

For update events, include:

- `changes`: array of change objects
  - `field`: string key (examples: `status_id`, `assigned_to_id`, `custom_field:42`)
  - `kind`: `"attribute"` or `"custom_field"`
  - `old`: `{ raw, text }`
  - `new`: `{ raw, text }`

For Issues, compute `raw` from journal details and derive `text` using the appropriate Redmine lookups (status name, user name, custom field formatted values, etc).

### Issue body

Always include tracker:

- `issue`: `{ id, tracker: { id, name }, subject, url }`

For update events, include journal metadata if available:

- `journal`: `{ id, notes }` (notes inclusion may be gated by permissions/config)

Full mode includes a snapshot:

- `issue_full`: serialized fields needed by the receiver (core fields + custom fields), plus helpful URLs.

### Time entry body

Minimal:

- `time_entry`: `{ id, issue_id, hours, activity: { id, name }, url }` (as available)

Full:

- `time_entry_full`: serialized fields needed by the receiver, plus helpful URLs.

### Delete events

Delete events must persist a snapshot at event time (before the record disappears), since later fetch is impossible.

## Authentication & API key monitoring

Per endpoint:

- Store `webhook_user_id` (reference only).
- On every delivery attempt:
  - Fetch the current API key for that user.
  - If missing, **auto-generate** one via Redmine’s API key mechanism.
  - Send it as `X-Redmine-API-Key`.

Monitoring:

- Never store the raw API key.
- Persist a fingerprint such as `sha256(api_key)` (and/or “missing”) to:
  - show when keys rotate
  - flag endpoints whose webhook user has no key / is inactive
  - correlate delivery failures to auth state

Error classification:

- Treat `401/403` as non-retryable by default (configurable), and surface prominently in the Admin deliveries UI.

## Delivery pipeline

### Persistent deliveries

For each (event, endpoint) match, create a delivery row:

- `status`: `pending | delivering | success | failed | dead`
- `attempts_count`
- `next_attempt_at`
- `payload_json` (immutable snapshot)
- last result fields (http status, error, response excerpt, duration)

### Async + DB-backed fallback

- Primary: enqueue an `ActiveJob` for delivery.
- Fallback: a rake task processes due deliveries from DB (cron/systemd timer).
  - Use row locking to avoid double-send when multiple runners exist.

### Retry policy (per endpoint)

Configurable:

- max attempts
- backoff parameters
- which HTTP statuses are retryable (ex: 408/429/5xx)
- timeouts and SSL verification

Success criteria: any `2xx`.

## Data model (tables)

Suggested tables:

- `webhook_endpoints`
- `webhook_endpoint_projects` (allowlist)
- `webhook_deliveries`

Each table should be namespaced/prefixed (plugin convention) to avoid collisions.

## Admin UI

Admin-only pages:

- Endpoints list + create/edit/delete
  - URL, enabled flag
  - webhook user
  - payload mode (minimal/full)
  - event/action toggles (issue/time_entry × create/update/delete)
  - project allowlist
  - retry policy
  - “send test” action (optional)
- Deliveries log
  - filters (endpoint/project/type/action/status/date)
  - replay delivery (resets status/attempts and enqueues)
  - retention/purge (manual + scheduled option)

## Future improvements (explicitly deferred)

- Additional headers (ex: `X-Redmine-Event-ID`, etc).
- Wiki events.
- Per-endpoint tracker allowlist.
- Per-endpoint custom headers/body templates.
- Signature/HMAC auth.

## Testing approach

- Unit tests for payload building:
  - Issue update diff from journal details (raw/text)
  - Time entry diff from `previous_changes`
- Unit tests for endpoint matching (project allowlist + event toggles).
- Integration-ish test for delivery retry state machine (without real HTTP, stub Net::HTTP).

## Compatibility verification (CI)

Compatibility is enforced via a CI matrix across supported Redmine versions using GitHub Actions and local/container runners.

- CI config: `.github/workflows/ci.yml`
- Runner: `tools/ci/run_redmine_compat.sh` (uses `REDMINE_DIR=/redmine` in prebaked mode)
