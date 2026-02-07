# PRD Analysis: Redmine Webhook Plugin (v1.0.0)

**Analysis Date:** 2025-12-23
**PRD Version:** v1.0.0
**Analyzed Document:** [redmine-webhook-plugin-prd-v100.md](redmine-webhook-plugin-prd-v100.md)

---

## Executive Summary

The PRD is **solid overall** (~100% complete for v1 implementation). All 4 critical gaps and 5 important gaps from this analysis have been addressed in PRD. Gaps #10 (fine-grained filtering), #11 (security assumptions), #12 (edge cases), and #13 (retry policy changes) have been documented.

**Status:**
- ✅ All CRITICAL gaps (FR-20a/b/c, FR-19a/b/c, FR-28a/b/c, NFR-6) have been incorporated
- ✅ All IMPORTANT gaps (FR-6b, NFR-7, FR-11a/b, NFR-8, NFR-5a/FR-5a/FR-23a) have been incorporated
- ✅ Gap #10 (fine-grained filtering) has been documented as known limitation in section 10.1
- ✅ Gap #11 (security assumptions) has been added as NFR-4a
- ✅ Gap #12 (edge cases) has been added to section 10 and FR-9 updated for UTC
- ✅ Gap #13 (retry policy changes) has been added as FR-22a/b
- All gaps from this analysis have been resolved

---

## 🔴 CRITICAL Gaps (must address before v1)

### 1. Delivery State Transition Logic (FR-20) ✅ **RESOLVED**

**Gap:** Incomplete state machine definition

**Status:** FR-20a/b/c added to PRD at lines 145-159.

**What was added:**
- FR-20a: Delivery lifecycle state transitions (pending → delivering → success/failed/dead)
- FR-20b: Endpoint state impact on deliveries (paused/resume/deleted behavior)
- FR-20c: Replay eligibility rules

**Original gap:** (Resolved - see above)

---

### 2. Webhook User Validity (FR-15-19) ✅ **RESOLVED**

**Gap:** Logic unclear when webhook_user is invalid

**Status:** FR-19a/b/c added to PRD at lines 126-140.

**What was added:**
- FR-19a: Webhook user validation on endpoint save (exists, active, API key warning)
- FR-19b: Webhook user validation at delivery time (deleted/locked handling, auto-gen)
- FR-19c: API key fingerprint calculation (sha256, rotation detection)

**Original gap:** (Resolved - see above)

---

### 3. Execution Mode Coordination (FR-26-28) ✅ **RESOLVED**

**Gap:** How do ActiveJob and DB runner coexist without double-delivery?

**Status:** FR-28a/b/c added to PRD at lines 187-202.

**What was added:**
- FR-28a: Execution mode selection (auto-detect ActiveJob, admin override)
- FR-28b: DB runner delivery claiming (status checks, atomic update, lock recovery)
- FR-28c: Double-delivery prevention (lifecycle, locking, pre-flight checks)

**Original gap:** (Resolved - see above)

---

### 4. Transaction Boundaries (FR-6) ✅ **RESOLVED**

**Gap:** Can webhook events escape transaction rollbacks?

**Status:** NFR-6 added to PRD at line 219.

**What was added:**
- NFR-6: Transactional consistency (after_commit callbacks, rollback prevention)

**Original gap:** (Resolved - see above)

---

## 🟡 IMPORTANT Gaps (should address or document)

### 5. Event Ordering (FR-6) ✅ **RESOLVED**

**Gap:** No ordering guarantee specified

**Status:** FR-6b (FIFO guarantee) added to PRD at lines 82-85.

**What was added:**
- FR-6b: Event ordering guarantee (FIFO for same resource, per-resource queue/lock)

**Original gap:** (Resolved - see above)

---

### 6. Bulk Operations (FR-6) ✅ **RESOLVED**

**Gap:** No strategy for bulk updates

**Status:** NFR-7 added to PRD at lines 220-223.

**What was added:**
- NFR-7: Bulk operation handling (normal queuing, concurrency limits, rate limiting)

**Original gap:** (Resolved - see above)

---

### 7. Change Tracking Scope (FR-11) ✅ **RESOLVED**

**Gap:** "Core fields + custom fields" is too vague

**Status:** FR-11a/b added to PRD at lines 105-110.

**What was added:**
- FR-11a: Change tracking scope for Issues (tracked vs not tracked fields)
- FR-11b: Change tracking scope for Time Entries (tracked fields)

**Original gap:** (Resolved - see above)

---

### 8. Payload Size Limits ✅ **RESOLVED**

**Gap:** No limits or truncation strategy specified

**Status:** NFR-8 added to PRD at lines 224-228.

**What was added:**
- NFR-8: Payload size limits (1MB threshold, 100 entry truncation, MEDIUMTEXT column)

**Original gap:** (Resolved - see above)

---

### 9. Observability Details (NFR-5, FR-23) ✅ **RESOLVED**

**Gap:** "Store only an excerpt" is too vague

**Status:** NFR-5a, FR-5a, FR-23a added to PRD.

**What was added:**
- NFR-5a: Delivery record observability (lines 214-218) - response excerpt, request/response headers, timing
- FR-5a: Test delivery indicator (lines 75-77) - is_test flag, visual indicator
- FR-23a: Delivery log search and filter (lines 168-176) - event_id, delivery_id, resource_id, HTTP status, is_test filters

**Original gap:** (Resolved - see above)

---

## 🟢 ACCEPTABLE Gaps for v1 (document as limitations)

### 10. Fine-grained Filtering ✅ **RESOLVED**

**Gap:** Fine-grained filtering not documented as known limitation

**Status:** Section 10.1 "Known Limitations (v1)" added to PRD at lines 251-254.

**What was added:**
- Section 10.1: Known Limitations (v1) documenting filtering limitations
- Future enhancements added to Section 12 (lines 267-270): issue priority/status allowlist, tracker allowlist, assignee/author allowlist

**Original gap:** (Resolved - see above)

**Current capability:**
- Project allowlist (empty = all projects)
- Event/action toggles (create/update/delete per object type)

**Common requests likely to arise:**
- **Issue priority filtering:** Only send webhooks for High/Critical priority issues
- **Issue status filtering:** Only send when status changes to Closed/Resolved
- **Author/assignee filtering:** Only send when specific user makes change
- **Per-project opt-out:** Global endpoint exists but project X wants to opt out

**Recommendation:**

Document as known v1 limitation:

```
## Known Limitations (v1)

- **Filtering:** v1 supports only project allowlist and event/action toggles.
  Fine-grained filtering (priority, status, assignee, tracker-specific) is
  not available. Receivers should implement their own filtering based on
  payload data.
```

Add to Section 12 (Future Enhancements):
- Per-endpoint issue priority allowlist/blocklist
- Per-endpoint issue status allowlist/blocklist
- Per-endpoint tracker allowlist (currently all trackers included)
- Per-endpoint assignee/author allowlist

---

### 11. Sensitive Data Handling (NFR-4) ✅ **RESOLVED**

**Gap:** No field-level redaction or data sensitivity controls

**Status:** NFR-4a added to PRD at lines 209-226.

**What was added:**
- NFR-4a: Security assumptions (v1) documenting:
  - All webhook receivers are FULLY TRUSTED with complete visibility
  - HTTPS STRONGLY RECOMMENDED (but HTTP ok in development mode)
  - No field-level redaction or data sensitivity controls in v1
  - Delivery logs contain immutable snapshots; admins must manually purge sensitive data
  - All Redmine admins have full access to all delivery logs (no project-scoped access)
  - Security recommendations for admins

**Original gap:** (Resolved - see above)

---

### 12. Edge Cases ✅ **RESOLVED**

**Gap:** Missing edge cases in Section 10 (Risks / Edge Cases)

**Status:** Section 10 extended with 5 edge cases (lines 260-265) and FR-9 updated for UTC (line 96).

**What was added:**
- **Circular webhooks:** Receivers must implement loop detection
- **Clock skew:** All occurred_at timestamps are UTC ISO8601
- **Deleted projects:** Deliveries contain stale snapshot; receivers should use payload as source of truth
- **Payload schema evolution:** Replayed deliveries use original schema version
- **Redmine core compatibility:** Plugin handles unknown fields by omitting from changes[] (safe degradation)
- FR-9 updated: `occurred_at` specifies ISO8601 UTC timestamp

**Original gap:** (Resolved - see above)

---

### 13. Retry Policy Changes ✅ **RESOLVED**

**Gap:** Effect on existing failed deliveries unclear

**Status:** FR-22a/b added to PRD at lines 167-174.

**What was added:**
- **FR-22a:** Retry policy change behavior - policy changes apply ONLY to new delivery attempts; existing deliveries retain original policy until manually replayed; manual replay applies current endpoint policy
- **FR-22b:** Global retry pause - admin can set 'deliveries_paused=true' flag to temporarily halt all delivery attempts; useful for maintenance windows or receiver outages

**Original gap:** (Resolved - see above)

---

## ✅ Strengths (well-defined areas)

The PRD demonstrates strong design in several areas:

1. **Clear scope boundaries**
   - Issues + Time Entries only (Wiki explicitly deferred)
   - v1 vs future enhancements clearly separated

2. **Excellent authentication model**
   - Webhook user + API key approach is Redmine-native
   - Auto-generation (FR-17) reduces admin burden
   - Fingerprint monitoring (FR-18) detects rotation

3. **Payload design**
   - Minimal vs Full modes address different receiver needs
   - `changes[]` with `{raw, text}` for old/new values is thoughtful (handles IDs + human-readable labels)
   - Stable envelope schema (FR-9) supports versioning

4. **Operational resilience**
   - Immutable snapshots (FR-7) enable replay
   - Replay capability (FR-24) is critical for production reliability
   - Dual execution modes (ActiveJob + DB runner) support diverse deployment environments

5. **Testability**
   - CI compatibility matrix is concrete (5.1.1, 5.1.10, 6.1.x)
   - Uses prebaked images for offline runner support
   - Success metrics defined (Section 9)

---

## 📋 Summary Recommendations

### Update History (2025-12-23)

**Status Update:** All CRITICAL and IMPORTANT gaps have been resolved in the PRD.

**Completed (CRITICAL):**
1. ✅ **FR-20a/b/c:** Complete delivery state machine with endpoint lifecycle impacts (lines 145-159)
2. ✅ **FR-19a/b/c:** Webhook user validation at save-time and delivery-time (lines 126-140)
3. ✅ **FR-28a/b/c:** Execution mode selection and coordination logic (lines 187-202)
4. ✅ **NFR-6:** Transactional consistency requirement (after_commit) (line 219)

**Completed (IMPORTANT):**
5. ✅ **FR-6b:** Event ordering guarantee - FIFO for same resource (lines 82-85)
6. ✅ **NFR-7:** Bulk operation handling strategy (lines 220-223)
7. ✅ **FR-11a/b:** Explicit change tracking scope table (lines 105-110)
8. ✅ **NFR-8:** Payload size limits and truncation (lines 224-228)
9. ✅ **NFR-5a, FR-5a, FR-23a:** Observability details (lines 75-77, 168-176, 214-218)

### Remaining Work (ACCEPTABLE - document as limitations)

10. ✅ **Document fine-grained filtering gap:** Added section 10.1 "Known Limitations (v1)" and future enhancements (lines 251-254, 267-270)
11. ✅ **Add security assumptions:** NFR-4a added to NFR-4 with security assumptions and recommendations (lines 209-226)
12. ✅ **Extend edge cases:** Section 10 extended with 5 edge cases and FR-9 updated for UTC (lines 96, 260-265)
13. ✅ **Retry policy changes:** FR-22a/b added for retry policy change behavior and global pause (lines 167-174)

---

## Overall Assessment

**Completeness: ~100%** (updated from ~99%)

The PRD provides a strong foundation with well-motivated features and clear scope. All CRITICAL and IMPORTANT gaps have been addressed:

- ✅ **State management** (delivery lifecycle FR-20a/b/c, endpoint deletion FR-20b)
- ✅ **Execution semantics** (transactional boundaries NFR-6, mode coordination FR-28a/b/c)
- ✅ **User validation** (webhook_user lifecycle FR-19a/b/c)
- ✅ **Event ordering** (FIFO guarantee FR-6b)
- ✅ **Bulk handling** (concurrency limits NFR-7)
- ✅ **Change tracking** (explicit scope FR-11a/b)
- ✅ **Payload limits** (truncation NFR-8)
- ✅ **Observability** (detailed metrics NFR-5a, FR-5a, FR-23a)

**Recommendation:** The PRD is **development-ready**. All gaps from this analysis have been addressed:
1. Review the detailed FRs added based on this analysis
2. ✅ Fine-grained filtering limitation documented in section 10.1 (gap #10)
3. ✅ Security assumptions added as NFR-4a (gap #11)
4. ✅ Edge cases added to section 10 and FR-9 updated for UTC (gap #12)
5. ✅ Retry policy change behavior added as FR-22a/b (gap #13)
