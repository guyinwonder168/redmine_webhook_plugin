# Redmine Webhook Plugin — Development Plan (v1)

| Field | Value |
| --- | --- |
| Scope | v1 as defined in [../redmine-webhook-plugin-prd-v100.md](../redmine-webhook-plugin-prd-v100.md) |
| Design | [../design/v1-redmine-webhook-plugin-design.md](../design/v1-redmine-webhook-plugin-design.md) |
| Admin UI wireframes | [../UIUX/v1-redmine-webhook-plugin-wireframes.md](../UIUX/v1-redmine-webhook-plugin-wireframes.md) |
| Target Redmine | **>= 5.1.1** (tested through **6.1.x**) |

[[_TOC_]]

This plan is structured as **vertical slices**: each slice is end-to-end, demoable, and suitable for a small MR.

## Redmine 7.0+ Compatibility

- Detect native webhooks via `defined?(::Webhook) && ::Webhook < ApplicationRecord`.
- When native exists, disable or bypass native delivery; the plugin remains authoritative.
- Use `RedmineWebhookPlugin::` for plugin service namespaces to avoid conflicts with native `Webhook`.

---

## Principles

- **Ship end-to-end slices** (capture → persist delivery → attempt → admin visibility).
- **Model-level hooks** (not controller-only) so events fire for UI + REST API + bulk edits.
- **Immutable payload snapshots** stored with each delivery.
- **No secrets at rest:** never store raw API keys.
- **Compatibility-first:** prefer stdlib + Redmine primitives; avoid version-sensitive internals where possible.

---

## Slice 1 — Endpoint CRUD + “Send test” + Dumb sink (HTTP/HTTPS + failure modes)

**Why:** unlocks fast iteration and validates connectivity/auth/SSL/retry plumbing before real event capture.

**PRD coverage:** FR-1..5, FR-7, FR-15..18 (baseline), FR-20..22 (baseline), FR-26 (baseline), NFR-4/5 (baseline)

### Deliverables (plugin)

- **DB tables + migrations**
  - `webhook_endpoints`
  - `webhook_endpoint_projects` (project allowlist)
  - `webhook_deliveries`
  - Indexes for common access paths (e.g. `(status,next_attempt_at)`, `(endpoint_id,occurred_at)`, `(project_id,occurred_at)`).
- **Admin UI (Admin-only)**
  - Endpoints list/create/edit/delete.
  - Fields (v1): `name,url,enabled,webhook_user_id,payload_mode`
  - Request options: `timeout_seconds`, `ssl_verify` (default true)
  - Event toggles: minimally enable “issue created” and “time_entry created” (expand in later slices).
  - Project allowlist editor (empty = all).
  - “Send test” action (creates a `webhook_delivery` row + enqueues delivery attempt).
- **Delivery attempt (baseline)**
  - `pending → delivering → success|failed`
  - Success: any `2xx`
  - Persist: `attempts_count`, `last_http_status`, `last_error`, `response_excerpt` (capped), `duration_ms`
- **Auth provider (baseline)**
  - Store only `webhook_user_id` on endpoint.
  - On attempt: fetch user API key; if missing, try to auto-generate (when permitted).
  - Persist only a fingerprint (e.g. `sha256(api_key)` or `"missing"`) on the delivery attempt metadata.
- **Minimal deliveries UI**
  - Admin deliveries list (at least: status, endpoint, occurred_at, last_http_status, last_error, attempts).

### Deliverables (tooling: dumb sink)

Add `tools/webhook_sink/` as a **dev/testing** receiver you can point endpoints at.

- **HTTP + HTTPS**
  - HTTP mode (default): `http://localhost:<port>/webhooks`
  - HTTPS mode: self-signed cert; support `ssl_verify` testing (verify ON should fail, OFF should succeed).
  - Auto-generate cert/key if not provided; persist under `tools/webhook_sink/certs/`.
- **Scenario-based responses** (easy failure simulation)
  - `success` → configurable `2xx`
  - `fail` → configurable non-2xx (e.g., `500`)
  - `rate_limit` → `429` + configurable `Retry-After`
  - `no_response` → sleep long enough to trigger client timeout
  - `drop` → accept socket then close without a response
  - `invalid_response` → write garbage/partial HTTP and close
  - `random` → weighted choice per request (seedable) for chaos testing
- **Per-request override**
  - Override scenario via query params (so you can test by changing only the endpoint URL in Redmine).
  - Always redact `X-Redmine-API-Key` in logs.
  - Optionally persist request bodies to `tools/webhook_sink/received/` (gitignored).
- **Docs**
  - `tools/webhook_sink/README.md` with copy/paste URLs for each scenario.

### Acceptance checks

- Create endpoint → “Send test” → delivery transitions to `success` against sink `scenario=success`.
- `ssl_verify=true` fails against sink HTTPS self-signed; `ssl_verify=false` succeeds.
- Sink `scenario=fail` records failure; `scenario=no_response` records timeout error; both visible in deliveries UI.

---

## Slice 2 — Issue “created” (minimal payload, endpoint matching)

**PRD coverage:** FR-6, FR-8, FR-9..10, FR-12

### Deliverables

- Event capture: `Issue.after_create_commit` emits deliveries for matching endpoints.
- Endpoint matching: enabled + action toggle + project allowlist (empty = all).
- Payload builder (minimal):
  - Envelope: `event_id,event_type,action,occurred_at,project,actor,delivery_mode`
  - `issue`: `{ id, tracker: { id, name }, subject, url }`
- Tests: endpoint matching + payload schema presence.

### Acceptance checks

- Create an issue (UI or REST) → deliveries created for matching endpoints.

---

## Slice 3 — Issue “updated” (Journal-based changes[] raw+text + full snapshot v1)

**PRD coverage:** FR-11, FR-13, risks/edge cases around journaling

### Deliverables

- Event capture: `Journal.after_create_commit` where `journalized_type == "Issue"`.
- `changes[]` derived from `JournalDetail`:
  - `{ field, kind, old:{raw,text}, new:{raw,text} }`
  - Support common fields + custom fields; unknown fields degrade gracefully.
- Full mode (phase 1): include `issue_full` snapshot (core fields + custom fields) kept stable.
- Tests: journal detail mapping + custom field display formatting.

### Acceptance checks

- Update issue status/assignee/custom field → webhook includes correct raw+text diffs.

---

## Slice 4 — Issue “deleted” (snapshot-at-delete)

**PRD coverage:** FR-14

### Deliverables

- Event capture: `Issue.after_destroy_commit`.
- Delete payload uses in-memory snapshot; does not depend on future DB fetch.
- Tests: delete event produces delivery with expected fields.

---

## Slice 5 — TimeEntry create/update/delete (minimal + changes[] + full snapshot)

**PRD coverage:** FR-6, FR-9, FR-11..13

### Deliverables

- Event capture: `TimeEntry.after_create_commit/after_update_commit/after_destroy_commit`.
- Update diffs: normalize `previous_changes` to `changes[]` with `{raw,text}`.
- Payload: minimal `time_entry` + full `time_entry_full`.
- Tests: create/update/delete and diff normalization.

---

## Slice 6 — Retries + Replay + DB-backed runner (no double-send)

**PRD coverage:** FR-20..28

### Deliverables

- Per-endpoint retry policy fields:
  - `max_attempts`, `backoff_base_seconds`, `backoff_max_seconds`, `retryable_statuses`
- State machine improvements:
  - Schedule `next_attempt_at` with exponential backoff.
  - Treat network/timeout errors as retryable; treat 401/403 as non-retryable by default.
- Concurrency safety:
  - Claim/lock semantics so the same delivery cannot be sent twice (ActiveJob vs rake runner).
- Rake runner:
  - `redmine_webhook_plugin:deliver_due` processes due deliveries in batches.
- Replay:
  - Admin action to re-queue an existing delivery.
- Tests:
  - backoff math; retryable vs non-retryable classification; claim prevents double-send.

---

## Slice 7 — Ops polish: auth health + retention/purge + safer logging

**PRD coverage:** FR-18..19, FR-23..25, NFR-5

### Deliverables

- Auth health indicators in Admin UI:
  - webhook user inactive/locked
  - API key missing/unavailable
  - repeated 401/403
- Retention:
  - manual purge UI action
  - optional scheduled purge rake task (days/limit parameters)
- Logging/data hygiene:
  - cap response excerpts; avoid persisting sensitive content.
- Tests: purge behavior; auth health derivation.

---

## Compatibility checkpoints (do continuously)

- Run CI matrix (5.1.1 / 5.1.10 / 6.1) early after Slice 1 lands.
- Keep API-key generation and journaling handling behind small adapters so differences across Redmine versions are isolated.
- Ensure payloads remain stable (add schema tests for required keys).

---

## Open questions to lock before coding

1. **URL fields:** should payload include absolute URLs only (requires host configured) or allow relative URLs when host is missing?
2. **Journal notes-only updates:** represent notes as a synthetic `changes` entry, or include notes only under `journal`?
3. **Replay semantics:** reset attempts to 0, or keep attempts and track replays separately?
