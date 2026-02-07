# PRD v1.0.0 Gap Analysis - Zero-Gaps Edition

**Analyzed:** redmine-webhook-plugin-prd-v100.md  
**Date:** 2025-12-24  
**Goal:** Identify all gaps and provide exact amendments to achieve a zero-gaps PRD  
**Philosophy:** Close gaps without over-engineering; pragmatic completeness

## FINALIZED DECISIONS

These decisions were confirmed through Q&A review on 2025-12-25:

| # | Decision | Answer |
|---|----------|--------|
| 1 | Schema version field | Include `schema_version` in v1 payloads |
| 2 | Sequence number mechanism | Microsecond timestamp (`Time.now.to_f * 1_000_000`) |
| 3 | Webhook user deleted | Auto-disable endpoint + notify admin |
| 4 | HTTP redirects | Follow up to 5 hops, reject HTTPS→HTTP downgrade |
| 5 | Retry policy storage | Store `retry_policy_snapshot` in delivery record |
| 6 | Stale lock timeout | 5 minutes fixed |
| 7 | Test deliveries default | Shown by default in delivery log |
| 8 | endpoint_deleted retention | 7 days (same as other statuses) |
| 9 | Bulk replay rate limit | Configurable per-endpoint |
| 10 | CSV export / API | CSV export only for v1 |
| 11 | Endpoint name uniqueness | Enforced (validation error on duplicate) |
| 12 | Max endpoints recommendation | Keep "50 endpoints" guidance |
| 13 | Replay retry policy source | Use current endpoint config |

---

## Summary

| Category | Count | Status After Amendment |
|----------|-------|------------------------|
| Critical | 5 | All closable with specific text |
| Logic | 6 | All closable with clarifications |
| Flow | 4 | All closable with additions |
| Minor | 7 | All closable with small edits |
| Already Correct | 8 | No changes needed |

**Total amendments required:** 22 specific text changes

---

## CRITICAL GAPS (5)

### C1. Missing Schema Version in Payload Envelope

**Location:** FR-9  
**Gap:** No `schema_version` field despite Section 10 acknowledging schema evolution risk.

**Amendment - Add to FR-9 bullet list:**
```markdown
  - `schema_version` (string, e.g., "1.0") - payload structure version; 
    receivers should handle unknown versions gracefully
```

---

### C2. Sequence Number Atomicity Unspecified

**Location:** FR-6b  
**Gap:** "assigned sequential 'sequence_number' at creation time" doesn't specify atomicity mechanism.

**Amendment - Add to FR-6b after "Processing order" section:**
```markdown
    - Sequence number assignment:
      - Scope: per (resource_type, resource_id) combination
      - Mechanism: database-level atomic increment using SELECT FOR UPDATE 
        or equivalent (prevents duplicate sequence numbers under concurrent load)
      - Initial value: 1 for first event on resource
```

---

### C3. Endpoint Lifecycle When Webhook User Deleted

**Location:** After FR-19c  
**Gap:** No specification for what happens to endpoint when its webhook_user is deleted from Redmine.

**Amendment - Add new FR-19d:**
```markdown
- **FR-19d:** Webhook user deletion impact on endpoints:
   - When a Redmine user is deleted:
     - Endpoints using that user as webhook_user are auto-disabled
     - Endpoint status shows error: "Webhook user deleted"
     - Pending/failed deliveries for that endpoint remain paused
   - Re-enabling requires selecting a new valid webhook_user
   - Admin UI lists affected endpoints when viewing deleted user's profile 
     (if Redmine supports this hook)
```

---

### C4. HTTP Redirect Handling Unspecified

**Location:** FR-21  
**Gap:** "Success is any HTTP 2xx" doesn't address 3xx redirects.

**Amendment - Replace FR-21 with:**
```markdown
- **FR-21:** HTTP response handling:
   - Success: any HTTP 2xx response
   - Redirects (3xx): follow up to 5 redirects; final response determines 
     success/failure; store final URL in delivery metadata
   - Client errors (4xx except retryable): non-retryable failure
   - Server errors (5xx): retryable per FR-22
```

---

### C5. Delivery Record Contents Incomplete

**Location:** FR-7  
**Gap:** Says "immutable payload snapshot" but Section 10 implies URL is also stored. Full contents not listed.

**Amendment - Replace FR-7 with:**
```markdown
- **FR-7:** For each matching endpoint, persist a delivery record containing:
   - `payload`: immutable JSON snapshot (serialized at event time)
   - `endpoint_url`: URL at delivery creation time (immutable; endpoint URL 
     changes do not affect existing deliveries)
   - `retry_policy_snapshot`: copy of endpoint's retry policy at creation time
   - `webhook_user_id`: reference to user for API key lookup
   - Metadata: event_id, resource_type, resource_id, sequence_number, 
     created_at, scheduled_at
```

---

## LOGIC GAPS (6)

### L1. Stale Lock Recovery Race Condition

**Location:** FR-20a, FR-28b  
**Gap:** "delivering → pending" on stale lock could cause duplicate if original worker succeeds late.

**Amendment - Add to Section 10.1 (Known Limitations):**
```markdown
- **Duplicate delivery edge case:** If a worker holds a delivery lock beyond 
  the 5-minute stale threshold (e.g., extremely slow network), the delivery 
  may be processed twice. Receivers MUST implement idempotency using 
  `event_id` to safely handle rare duplicates.
```

---

### L2. Test Delivery Default Visibility

**Location:** FR-23a  
**Gap:** "Filter by is_test flag" doesn't specify default behavior.

**Amendment - Add to FR-23a after filter list:**
```markdown
       - Default view: all deliveries shown (including test)
       - Test deliveries excluded from success rate metrics (Section 9)
```

---

### L3. endpoint_deleted Purge Eligibility

**Location:** FR-25a  
**Gap:** `endpoint_deleted` status not in purge_statuses list.

**Amendment - Replace FR-25a purge_statuses line:**
```markdown
   - purge_statuses: ['success', 'failed', 'dead', 'endpoint_deleted']
   - Note: endpoint_deleted deliveries are audit records; consider longer 
     retention (retention_days_endpoint_deleted: 90 default)
```

---

### L4. Event Action Naming Inconsistency

**Location:** FR-2, FR-5, FR-6b, FR-8 vs FR-9  
**Gap:** FR-9 uses past tense (`created`/`updated`/`deleted`), other sections use present tense.

**Amendment - Standardize all references to past tense:**
- FR-2: "enabled events/actions (issue/time_entry × created/updated/deleted)"
- FR-5, Section 5: Use "created/updated/deleted" consistently
- FR-8: "event/action enabled" is acceptable (refers to toggle, not event name)

**Add clarification to FR-9:**
```markdown
   - Note: action values use past tense (created/updated/deleted) to indicate 
     the event has already occurred
```

---

### L5. Configuration Change Impact on Pending Deliveries

**Location:** After FR-3  
**Gap:** What happens to pending deliveries when endpoint config changes?

**Amendment - Add new FR-3a:**
```markdown
- **FR-3a:** Endpoint configuration change impact:
   - `payload_mode` change: applies to NEW events only; pending deliveries 
     use mode from creation time
   - `project_allowlist` change: filtering applied at event capture time; 
     pending deliveries are not re-filtered
   - `enabled` toggle: takes effect immediately for all pending/failed 
     deliveries
   - `url` change: NEW deliveries use new URL; pending deliveries use 
     original URL (per FR-7)
   - `retry_policy` change: per FR-22a (new attempts only)
```

---

### L6. Actor Capture for System/Automated Events

**Location:** FR-9  
**Gap:** `actor` is "when available" but doesn't specify what happens for automated/system events.

**Amendment - Add clarification to FR-9 actor bullet:**
```markdown
   - `actor` (when available): `{ id, login, name }`
     - For user-initiated events: the authenticated user
     - For REST API events: the API key owner
     - For system/automated events (e.g., scheduled tasks): null
```

---

## FLOW GAPS (4)

### F1. Bulk Replay Missing

**Location:** FR-24  
**Gap:** Only singular replay specified; receiver outages could create hundreds of failed deliveries.

**Amendment - Add FR-24a:**
```markdown
- **FR-24a:** Bulk replay:
   - Admin can select multiple deliveries by filter criteria and replay all
   - Confirmation required: "Replay N deliveries to endpoint X?"
   - Rate limiting: bulk replay queues max 100 deliveries per minute per 
     endpoint to prevent overwhelming receivers
   - Bulk replay resets all selected to 'pending' with current retry policy
```

---

### F2. Delivery Log Pagination Missing

**Location:** FR-23  
**Gap:** No pagination specified for potentially large delivery logs.

**Amendment - Add to FR-23:**
```markdown
   - Pagination: 50 deliveries per page (configurable in plugin settings)
   - Sort: newest first by default; sortable by any column
```

---

### F3. Destructive Action Confirmation Missing

**Location:** FR-4  
**Gap:** Delete endpoint affects all associated deliveries but no confirmation specified.

**Amendment - Replace FR-4:**
```markdown
- **FR-4:** Admin can delete an endpoint.
   - Confirmation required: "Delete endpoint 'X'? This will soft-delete N 
     associated deliveries."
   - Soft-deleted deliveries marked with status 'endpoint_deleted' (FR-20b)
```

---

### F4. Deep Link to Delivery Record Missing

**Location:** FR-23  
**Gap:** No stable URL for sharing/debugging specific deliveries.

**Amendment - Add to FR-23:**
```markdown
   - Each delivery has stable URL: `/admin/webhooks/deliveries/:id`
   - URL can be shared for debugging/support purposes
```

---

## MINOR GAPS (7)

### M1. Endpoint Name Uniqueness Enforcement Level

**Location:** FR-2  
**Gap:** "should be unique for admin clarity" is ambiguous.

**Amendment - Clarify in FR-2:**
```markdown
   - endpoint names must be unique (validation error on duplicate); 
     URLs may be duplicated
```

---

### M2. Outbound User-Agent Header Not Defined

**Location:** NFR-5a  
**Gap:** "store User-Agent" but outbound User-Agent value not specified.

**Amendment - Add to FR-15 or create FR-15a:**
```markdown
- **FR-15a:** Outbound request headers:
   - `Content-Type: application/json`
   - `User-Agent: RedmineWebhook/<plugin_version> (Redmine/<redmine_version>)`
   - `X-Redmine-API-Key: <webhook_user_api_key>`
   - `X-Redmine-Event-ID: <event_id>` (for receiver-side idempotency)
```

---

### M3. Project Deletion Impact on Allowlist

**Location:** FR-2, Section 10  
**Gap:** What happens to endpoint's project_allowlist when a project in it is deleted?

**Amendment - Add to Section 10 (Risks / Edge Cases):**
```markdown
- **Deleted projects in allowlist:** When a project is deleted from Redmine, 
  it is automatically removed from all endpoint project_allowlists. If an 
  allowlist becomes empty after removal, the endpoint matches all projects 
  (per FR-8 empty = all). Admin should review endpoint configuration after 
  project deletion.
```

---

### M4. Timezone Display in UI

**Location:** FR-23  
**Gap:** Timestamps are UTC but admin UI display not specified.

**Amendment - Add to FR-23:**
```markdown
   - Timestamps displayed in admin's browser timezone (standard Redmine behavior)
   - Hover tooltip shows UTC value
```

---

### M5. Empty changes[] for Update Without Changes

**Location:** FR-11  
**Gap:** What if update event fires but no tracked fields changed (e.g., only notes added)?

**Amendment - Add clarification to FR-11:**
```markdown
   - If update event has no tracked field changes, changes[] is empty array
   - Event still fires (useful for receivers tracking notes via last_note in 
     full mode)
```

---

### M6. Maximum Endpoints Per Installation

**Location:** FR-1, FR-2  
**Gap:** No specified limit; could affect performance at scale.

**Amendment - Add to NFR-2 (Performance):**
```markdown
   - Recommended maximum: 50 endpoints per installation (not enforced; 
     admin responsibility to monitor performance)
   - Each event creates one delivery per matching endpoint (N endpoints = 
     N deliveries per event)
```

---

### M7. Delivery Attempt Count Visibility

**Location:** FR-20, FR-23  
**Gap:** Status lifecycle defined but attempt count display not specified.

**Amendment - Add to FR-23 (Delivery log UI):**
```markdown
   - Delivery record displays: attempt_count (current/max), next_retry_at 
     (for failed status)
```

---

## ALREADY CORRECT - NO CHANGES NEEDED (8)

These design decisions are **appropriately scoped** and should NOT be "enhanced":

| Decision | Why It's Correct |
|----------|------------------|
| Soft FIFO ordering (FR-6b) | Strict FIFO requires distributed locking; ~95% is pragmatic |
| Global admin config only | Per-project adds significant complexity; correct for v1 |
| No HMAC/signature auth | API key sufficient for trusted receivers; HMAC in v1.1 |
| No raw API key storage | Correct security posture |
| Receiver-side responsibility | Circular webhook detection, timestamp handling belong to receiver |
| Immutable payload snapshots | Simplifies replay, prevents mutation bugs |
| after_commit callbacks (NFR-6) | Prevents phantom webhooks from rollbacks |
| Soft-delete for endpoint deletion | Preserves audit trail correctly |

---

## EXPLICITLY DEFER (Add to Section 3 - Non-goals)

These should be explicitly listed to prevent scope creep:

**Amendment - Add to Section 3:**
```markdown
- Delivery statistics dashboard (metrics visible via delivery log filters only).
- Endpoint health checks (periodic connectivity pings).
- Event batching (one HTTP request per event).
- Audit log for endpoint configuration changes.
- Immediate retry button (use bulk replay instead).
- Endpoint tagging/grouping.
```

---

## VERIFICATION CHECKLIST

After applying all amendments, verify:

- [ ] FR-9 includes `schema_version`
- [ ] FR-6b specifies atomic sequence_number mechanism
- [ ] FR-19d covers webhook_user deletion → endpoint impact
- [ ] FR-21 covers redirect handling
- [ ] FR-7 lists complete delivery record contents
- [ ] Section 10.1 documents duplicate delivery edge case
- [ ] FR-23a specifies test delivery default visibility
- [ ] FR-25a includes endpoint_deleted in purge eligibility
- [ ] Action naming is consistently past tense
- [ ] FR-3a covers configuration change impacts
- [ ] FR-9 clarifies actor for system events
- [ ] FR-24a adds bulk replay
- [ ] FR-23 includes pagination, deep links, timezone display, attempt count
- [ ] FR-4 requires confirmation for delete
- [ ] FR-2 specifies name uniqueness is enforced (error)
- [ ] FR-15a defines outbound headers including User-Agent
- [ ] Section 10 covers project deletion impact on allowlist
- [ ] FR-11 handles empty changes[] case
- [ ] NFR-2 recommends maximum endpoints
- [ ] Section 3 explicitly lists deferred items

---

## AMENDMENT SUMMARY BY SECTION

| Section | Amendments |
|---------|------------|
| 3) Non-goals | Add 6 deferred items |
| 6.1 FR-2 | Clarify name uniqueness |
| 6.1 FR-3a | NEW: config change impact |
| 6.1 FR-4 | Add confirmation requirement |
| 6.2 FR-6b | Add sequence_number atomicity |
| 6.2 FR-7 | Expand delivery record contents |
| 6.3 FR-9 | Add schema_version, clarify actor |
| 6.3 FR-11 | Add empty changes[] case |
| 6.4 FR-15a | NEW: outbound headers |
| 6.4 FR-19d | NEW: webhook_user deletion impact |
| 6.5 FR-21 | Add redirect handling |
| 6.5 FR-23 | Add pagination, deep link, timezone, attempt count |
| 6.5 FR-23a | Add test delivery defaults |
| 6.5 FR-24a | NEW: bulk replay |
| 6.5 FR-25a | Add endpoint_deleted purge |
| 7) NFR-2 | Add recommended max endpoints |
| 10) Risks | Add project deletion impact |
| 10.1) Limitations | Add duplicate delivery edge case |

**Total: 22 specific amendments across 18 sections**

---

## POST-AMENDMENT VALIDATION

After applying all amendments, re-analyze with these questions:

1. **Can implementation proceed without ambiguity?** → Yes, all behaviors specified
2. **Are edge cases documented or explicitly deferred?** → Yes
3. **Is scope creep prevented?** → Yes, Non-goals expanded
4. **Are receiver responsibilities clear?** → Yes, documented in Limitations
5. **Is the PRD internally consistent?** → Yes, naming standardized

**Expected result of re-analysis: 0 gaps**
