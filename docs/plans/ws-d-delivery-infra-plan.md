# Workstream D: Delivery Infrastructure - Implementation Plan

> **Status**: Ready for Task Manager delegation  
> **Original Plan**: `docs/plans/ws-d-delivery-infra.md`  
> **Strategy**: TDD with cross-version verification (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)

## Executive Summary

**Goal**: Build HTTP delivery infrastructure for webhook plugin - send payloads to endpoints, handle errors, retry with exponential backoff, and manage API key authentication.

**Scope**: 12 implementation tasks + 1 verification task  
**Estimated Time**: 4-6 hours  
**Files Created**: ~20 files (10 services + 10 tests)  
**Dependencies**: Requires P0 Foundation (RedmineWebhookPlugin::Webhook::Endpoint, RedmineWebhookPlugin::Webhook::Delivery models)

## Architecture Overview

```
app/services/webhook/
├── delivery_result.rb        # Value object for HTTP response
├── error_classifier.rb        # Exception → error code mapping
├── retry_policy.rb            # Exponential backoff calculator
├── api_key_resolver.rb        # User API token management
├── headers_builder.rb         # HTTP headers construction
└── http_client.rb             # Net::HTTP wrapper with retry logic

test/unit/webhook/
├── delivery_result_test.rb
├── error_classifier_test.rb
├── retry_policy_test.rb
├── api_key_resolver_test.rb
├── headers_builder_test.rb
└── http_client_test.rb
```

### Service Responsibilities

| Service | Purpose | Key Methods |
|---------|---------|-------------|
| **DeliveryResult** | Immutable result wrapper | `.success()`, `.failure()`, `#success?` |
| **ErrorClassifier** | Map exceptions to codes | `.classify(exception)`, `.classify_http_status(status)` |
| **RetryPolicy** | Backoff calculation | `#should_retry?()`, `#next_delay()`, `#next_retry_at()` |
| **ApiKeyResolver** | Token management | `.resolve(user)`, `.generate_if_missing(user)`, `.fingerprint(key)` |
| **HeadersBuilder** | Standard headers | `.build(event_id:, api_key:, ...)` |
| **HttpClient** | HTTP POST with retry | `#post(url:, payload:, headers:)` |

## Implementation Phases

### Phase 1: Value Objects & Error Handling (Tasks 1-2)

**Objective**: Build foundational types for HTTP responses and error classification

#### Task 1: DeliveryResult Value Object
- **Status**: Complete
- **Files**: `app/services/webhook/delivery_result.rb`, `test/unit/webhook/delivery_result_test.rb`
- **Tests**: 5 tests
- **Features**:
  - Immutable success/failure wrapper
  - Factory methods: `.success()`, `.failure()`
  - Response body truncation (2KB max for storage)
  - Attributes: `http_status`, `response_body`, `error_code`, `error_message`, `duration_ms`, `final_url`
- **Verification**:
  - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 2: ErrorClassifier Service
- **Status**: Complete
- **Files**: `app/services/webhook/error_classifier.rb`, `test/unit/webhook/error_classifier_test.rb`
- **Tests**: 12 tests
- **Features**:
  - Map Ruby exceptions to error codes
  - Classify HTTP status codes (2xx → nil, 4xx → client_error, 5xx → server_error)
  - Error codes: `connection_timeout`, `read_timeout`, `connection_refused`, `connection_reset`, `dns_error`, `ssl_error`, `unknown_error`
- **Verification**:
  - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

**Estimated Time**: 30-45 minutes  
**Acceptance Criteria**:
- ✅ All tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
- ✅ Both services properly required in `init.rb`
- ✅ Error codes match plan specification

---

### Phase 2: Retry Infrastructure (Tasks 3-5)

**Objective**: Implement exponential backoff with jitter and retry decision logic

#### Task 3: RetryPolicy - Basic Structure
- **Status**: Complete
- **Files**: `app/services/webhook/retry_policy.rb`, `test/unit/webhook/retry_policy_test.rb`
- **Tests**: 4 tests
- **Features**:
  - Initialize with config hash (default or custom)
  - Attributes: `max_attempts` (5), `base_delay` (60s), `max_delay` (3600s), `retryable_statuses` ([408, 429, 500, 502, 503, 504])
  - Symbol/string key normalization
- **Verification**:
  - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 4: RetryPolicy - Retryable Logic
- **Status**: Complete
- **Files**: Modify existing `retry_policy.rb`, `retry_policy_test.rb`
- **Tests**: +6 tests (10 total)
- **Features**:
  - `#retryable?(http_status:, error_code:, ssl_verify:)` - Check if error is retryable
  - `#should_retry?(attempt_count:, ...)` - Combine attempt count with retryability
  - Retryable error codes: timeouts, connection errors, DNS errors
  - SSL errors only retryable if `ssl_verify: false`
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 5: RetryPolicy - Backoff Calculator
- **Status**: Complete
- **Files**: Modify existing `retry_policy.rb`, `retry_policy_test.rb`
- **Tests**: +4 tests (14 total)
- **Features**:
  - `#next_delay(attempt_count, jitter:)` - Exponential backoff: `base_delay * (2 ** attempt)`
  - `#next_retry_at(attempt_count, jitter:)` - Returns `Time` object
  - Jitter: 0.8-1.2 random factor to prevent thundering herd
  - Respects `max_delay` cap
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

**Estimated Time**: 45-60 minutes  
**Acceptance Criteria**:
- ✅ Exponential backoff: 60s → 120s → 240s → 480s (without jitter)
- ✅ Jitter stays within ±20% range
- ✅ Retry logic respects attempt limits
- ✅ All 14 tests pass on 4 Redmine versions (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)

---

### Phase 3: API Key Management (Tasks 6-8)

**Objective**: Resolve user API tokens, auto-generate when missing, fingerprint for logging

#### Task 6: ApiKeyResolver - Basic Lookup
- **Status**: Complete
- **Files**: `app/services/webhook/api_key_resolver.rb`, `test/unit/webhook/api_key_resolver_test.rb`
- **Tests**: 5 tests
- **Features**:
  - `.resolve(user_or_id)` - Find existing API token
  - Accepts User object or user_id
  - Returns token value or `nil`
  - Uses `Token.find_by(user_id:, action: "api")`
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 7: ApiKeyResolver - Auto-Generation
- **Status**: Complete
- **Files**: Modify existing `api_key_resolver.rb`, `api_key_resolver_test.rb`
- **Tests**: +4 tests (9 total)
- **Features**:
  - `.generate_if_missing(user_or_id)` - Create token if none exists
  - Checks `Setting.rest_api_enabled?` before creation
  - Raises `RestApiDisabledError` if disabled
  - Raises `UserNotFoundError` if user invalid
  - Returns existing token if present (idempotent)
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 8: ApiKeyResolver - Fingerprinting
- **Status**: Complete
- **Files**: Modify existing `api_key_resolver.rb`, `api_key_resolver_test.rb`
- **Tests**: +4 tests (13 total)
- **Features**:
  - `.fingerprint(api_key)` - SHA256 hash for secure logging
  - Returns "missing" for nil/empty keys
  - Consistent hashing (same key → same fingerprint)
  - Never logs actual API key value
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

**Estimated Time**: 45-60 minutes  
**Acceptance Criteria**:
- ✅ Finds existing tokens without creating duplicates
- ✅ Auto-generation respects REST API setting
- ✅ Fingerprints are 64-character hex strings
- ✅ All 13 tests pass on 4 Redmine versions (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)

---

### Phase 4: HTTP Infrastructure (Tasks 9-12)

**Objective**: Build Net::HTTP wrapper with headers, timeouts, redirects, and error handling

#### Task 9: HeadersBuilder Service
- **Status**: Complete
- **Files**: `app/services/webhook/headers_builder.rb`, `test/unit/webhook/headers_builder_test.rb`
- **Tests**: 9 tests
- **Features**:
  - `.build(event_id:, event_type:, action:, api_key:, delivery_id:, custom_headers:)`
  - Standard headers:
    - `Content-Type: application/json; charset=utf-8`
    - `User-Agent: RedmineWebhook/1.0.0 (Redmine/5.1.0)`
    - `X-Redmine-Event-ID: <uuid>`
    - `X-Redmine-Event: issue.created`
    - `X-Redmine-API-Key: <token>` (if provided)
    - `X-Redmine-Delivery: <delivery_id>` (for tracking)
  - Merges custom headers from endpoint config
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 10: HttpClient - Basic Structure
- **Status**: Complete
- **Files**: `app/services/webhook/http_client.rb`, `test/unit/webhook/http_client_test.rb`
- **Tests**: 7 tests
- **Features**:
  - `#initialize(timeout:, ssl_verify:)` - Configure client
  - `#post(url:, payload:, headers:)` - Returns DeliveryResult
  - Uses `Net::HTTP` with configurable timeouts
  - SSL verification (VERIFY_PEER or VERIFY_NONE)
  - Measures duration with monotonic clock
  - Returns success for 2xx, failure for 4xx/5xx
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 11: HttpClient - Timeout Handling
- **Status**: Complete
- **Files**: Modify existing `http_client.rb`, `http_client_test.rb`
- **Tests**: +5 tests (12 total)
- **Features**:
  - Catch `Timeout::Error`, `Net::OpenTimeout`, `Net::ReadTimeout`
  - Catch `Errno::ECONNREFUSED`, `Errno::ECONNRESET`
  - Catch `SocketError` (DNS failures)
  - Catch `OpenSSL::SSL::SSLError`
  - Use ErrorClassifier to map exceptions
  - Always measure duration, even on failure
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

#### Task 12: HttpClient - Redirect Following
- **Status**: Complete
- **Files**: Modify existing `http_client.rb`, `http_client_test.rb`
- **Tests**: +6 tests (18 total)
- **Features**:
  - Follow 301, 302, 303, 307, 308 redirects (max 5)
  - Track final URL after redirects
  - Reject HTTPS → HTTP downgrade (security)
  - Allow HTTP → HTTPS upgrade
  - Return `too_many_redirects` error after 5 hops
  - Return `insecure_redirect` error for downgrades
 - **Verification**:
   - Tests pass on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

**Estimated Time**: 90-120 minutes  
**Acceptance Criteria**:
- ✅ HeadersBuilder includes all standard webhook headers
- ✅ HttpClient successfully POSTs JSON payloads
- ✅ All network errors properly classified
- ✅ Redirects followed with security checks
- ✅ All 18 HttpClient tests pass on 4 Redmine versions (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)
- ✅ `webmock` properly configured in test environment

---

### Phase 5: Integration Verification (Task 13)

**Objective**: Verify all services work together across Redmine versions

#### Task 13: Cross-Version Testing & Console Verification
- **Actions**:
  1. Run full test suite on 5.1.0: `VERSION=5.1.0 tools/test/run-test.sh`
  2. Run full test suite on 5.1.10: `VERSION=5.1.10 tools/test/run-test.sh`
  3. Run full test suite on 6.1.0: `VERSION=6.1.0 tools/test/run-test.sh`
  4. Run full test suite on 7.0.0-dev: `VERSION=7.0.0-dev tools/test/run-test.sh`
  5. Manual Rails console verification (see verification script below)

**Console Verification Script**:
```ruby
# Load Rails console: cd .redmine-test/redmine-5.1.0 && bundle exec rails console -e test

# Test DeliveryResult
result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(http_status: 200, duration_ms: 100)
result.success? # => true

# Test ErrorClassifier
RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(Timeout::Error.new) # => "connection_timeout"
RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(500) # => "http_server_error"

# Test RetryPolicy
policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new
policy.should_retry?(attempt_count: 0, error_code: "connection_timeout") # => true
policy.next_delay(0) # => ~60 (with jitter)

# Test ApiKeyResolver
user = User.first
RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint("test-key") # => SHA256 hash

# Test HeadersBuilder
RedmineWebhookPlugin::Webhook::HeadersBuilder.build(event_id: "test-123") # => Hash with headers

exit
```

**Estimated Time**: 30 minutes  
**Acceptance Criteria**:
- ✅ All 187+ existing tests still pass
- ✅ All 68+ new Workstream D tests pass (5+12+14+13+9+18 = 71)
- ✅ Tests pass on Redmine 5.1.0, 5.1.10, 6.1.0, and 7.0.0-dev
- ✅ Console verification completes without errors
- ✅ All services properly loaded via `init.rb`

---

## Critical Implementation Notes

### Namespace Strategy
**IMPORTANT**: Use `module RedmineWebhookPlugin::Webhook` for services to avoid conflicts with Redmine 7.0+ native `Webhook` class.

The plan uses:
```ruby
module RedmineWebhookPlugin
  module Webhook
    class DeliveryResult
      # ...
    end
  end
end
```

This matches the strategy in `AGENTS.md` and keeps namespaces consistent with existing plugin models.

### TDD Workflow (MANDATORY)
For **EVERY** task:
1. ✅ **Write test FIRST** (copy from plan document)
2. ✅ **Run test on 5.1.0** - verify FAIL
3. ✅ **Write implementation** (minimal code to pass)
4. ✅ **Run test on 5.1.0** - verify PASS
5. ✅ **Cross-version test** (5.1.10, 6.1.0, 7.0.0-dev) - verify PASS on all
6. ✅ **Update `init.rb`** (add require_dependency for new services)
7. ✅ **Commit atomically** with message format: `feat(d): <description>`

### Podman Test Command Pattern
```bash
# Template for running single test file
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-<VERSION>:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/<VERSION>:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:<VERSION> \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/<TEST_FILE>.rb -v'
```

Replace `<VERSION>` with: `5.1.0`, `5.1.10`, `6.1.0`, or `7.0.0-dev`  
Replace `<TEST_FILE>` with: `delivery_result_test`, `error_classifier_test`, etc.

### WebMock Setup
HttpClient tests require `webmock` gem. Add to `test/test_helper.rb`:
```ruby
# At top of file
begin
  require "webmock/minitest"
  WebMock.disable_net_connect!(allow_localhost: true)
rescue LoadError
  # WebMock not available in this environment
end
```

Or add to Gemfile:
```ruby
group :test do
  gem "webmock"
end
```

### init.rb Updates
After each service creation, update `init.rb`:
```ruby
# init.rb
Rails.application.config.to_prepare do
  # Existing requires...
  require_dependency File.expand_path("../app/models/webhook", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/endpoint", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/delivery", __FILE__)
  
  # Add new service requires here
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/retry_policy", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/api_key_resolver", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/headers_builder", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/http_client", __FILE__)
end
```

---

## Delegation Strategy

### Task Manager Agent Instructions

**Agent**: `subagents/core/task-manager`

**Prompt Template**:
```
Implement Workstream D: Delivery Infrastructure for Redmine webhook plugin.

Source Plan: docs/plans/ws-d-delivery-infra.md
Implementation Plan: docs/plans/ws-d-delivery-infra-plan.md

Follow strict TDD workflow:
1. Write test first (copy from source plan)
2. Verify test fails on Redmine 5.1.0
3. Write minimal implementation
4. Verify test passes on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
5. Update init.rb if new service
6. Commit with format: feat(d): <description>

Implement in phase order:
- Phase 1: DeliveryResult + ErrorClassifier (Tasks 1-2)
- Phase 2: RetryPolicy full implementation (Tasks 3-5)
- Phase 3: ApiKeyResolver full implementation (Tasks 6-8)
- Phase 4: HeadersBuilder + HttpClient (Tasks 9-12)
- Phase 5: Integration verification (Task 13)

Use namespace: module RedmineWebhookPlugin::Webhook

All tests must pass on Redmine 5.1.0, 5.1.10, 6.1.0, and 7.0.0-dev before proceeding to next task.
```

### Expected Deliverables

**Files Created** (20 total):
- `app/services/webhook/delivery_result.rb`
- `app/services/webhook/error_classifier.rb`
- `app/services/webhook/retry_policy.rb`
- `app/services/webhook/api_key_resolver.rb`
- `app/services/webhook/headers_builder.rb`
- `app/services/webhook/http_client.rb`
- `test/unit/webhook/delivery_result_test.rb`
- `test/unit/webhook/error_classifier_test.rb`
- `test/unit/webhook/retry_policy_test.rb`
- `test/unit/webhook/api_key_resolver_test.rb`
- `test/unit/webhook/headers_builder_test.rb`
- `test/unit/webhook/http_client_test.rb`

**Files Modified**:
- `init.rb` (add 6 require_dependency statements)
- `test/test_helper.rb` (add webmock if needed)
- `CHANGELOG.md` (document new features)

**Git Commits** (12 minimum):
1. `feat(d): add DeliveryResult value object`
2. `feat(d): add ErrorClassifier service`
3. `feat(d): add RetryPolicy service basic structure`
4. `feat(d): add RetryPolicy retryable? and should_retry? methods`
5. `feat(d): add RetryPolicy exponential backoff with jitter`
6. `feat(d): add ApiKeyResolver service with basic lookup`
7. `feat(d): add ApiKeyResolver auto-generation with REST API check`
8. `feat(d): add ApiKeyResolver fingerprinting with SHA256`
9. `feat(d): add HeadersBuilder service`
10. `feat(d): add HttpClient service with basic POST`
11. `test(d): add HttpClient timeout and error handling tests`
12. `feat(d): add HttpClient redirect following with security checks`

---

## Success Metrics

### Test Coverage
- **Minimum Tests**: 68 new tests
  - DeliveryResult: 5 tests
  - ErrorClassifier: 12 tests
  - RetryPolicy: 14 tests
  - ApiKeyResolver: 13 tests
  - HeadersBuilder: 9 tests
  - HttpClient: 18 tests

### Cross-Version Compatibility
- ✅ Redmine 5.1.0 (Ruby 3.2.2, Rails 6.1)
- ✅ Redmine 5.1.10 (Ruby 3.2.2, Rails 6.1)
- ✅ Redmine 6.1.0 (Ruby 3.3.4, Rails 7.2)
- ✅ Redmine 7.0.0-dev (Ruby 3.3.4+, Rails 7.2+)

### Code Quality
- ✅ Ruby 2-space indentation
- ✅ `snake_case` file names
- ✅ `CamelCase` class names
- ✅ Proper error handling with custom exceptions
- ✅ No monkey patches
- ✅ Thread-safe implementations

### Functional Requirements
- ✅ DeliveryResult wraps HTTP responses immutably
- ✅ ErrorClassifier maps all network exceptions
- ✅ RetryPolicy calculates exponential backoff (60s → 3600s max)
- ✅ ApiKeyResolver finds/generates API tokens
- ✅ HeadersBuilder creates standard webhook headers
- ✅ HttpClient POSTs JSON with timeout/retry/redirect handling

---

## Risk Mitigation

### Known Issues

1. **WebMock Dependency**
   - **Risk**: May not be in default Gemfile
   - **Mitigation**: Add conditional require in test_helper.rb
   - **Fallback**: Skip HttpClient tests if unavailable (not ideal)

2. **Redmine 7.0.0-dev Native Webhook Conflict**
   - **Risk**: Native `Webhook` class conflicts with plugin services
   - **Mitigation**: Services and models use `RedmineWebhookPlugin::Webhook::` namespace
   - **Note**: Plugin detects and disables native webhooks via `RedmineWebhookPlugin.disable_native_webhooks!`

3. **Namespace Confusion**
   - **Risk**: Mixing `RedmineWebhookPlugin::Webhook::` vs `RedmineWebhookPlugin::Webhook::`
   - **Mitigation**: Use `RedmineWebhookPlugin::Webhook::` everywhere in docs and code

4. **Cross-Version API Differences**
   - **Risk**: Token/Setting APIs may differ across Redmine versions
   - **Mitigation**: Test on all 4 versions, check Redmine compatibility docs

---

## Verification Checklist

Before marking Workstream D complete:

- [x] All 12 tasks implemented (Tasks 1-12)
- [x] All 68+ tests pass on 4 Redmine versions (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)
- [x] 12 atomic commits with clear messages
- [x] init.rb properly loads all 6 services
- [ ] Console verification script runs without errors
- [x] No test failures in existing test suite (regression check)
- [x] CHANGELOG.md updated with delivery infrastructure features
- [x] Code follows Ruby/Rails conventions
- [x] No hardcoded values (use constants)
- [x] Thread-safe implementations

---

## Post-Implementation Tasks

After Workstream D completion:

1. **Update CONTINUITY.md**
   - Mark Workstream D as complete
   - Document any deviations from plan
   - Note next workstream dependencies

2. **Update Main README** (if needed)
   - Document HTTP delivery features
   - Add configuration examples for retry policies

3. **Prepare for Workstream E** (if exists)
   - Verify delivery infrastructure works with dispatcher
   - Test end-to-end flow: event → payload → HTTP POST

---

## Quick Reference

### File Locations
```
app/services/webhook/         # All service objects here
test/unit/webhook/            # All service tests here
init.rb                       # Service loading
docs/plans/ws-d-delivery-infra.md  # Original TDD plan
```

### Test Commands
```bash
# Single test
VERSION=5.1.0 && podman run --rm \
  -v $PWD/.redmine-test/redmine-$VERSION:/redmine:rw \
  -v $PWD:/redmine/plugins/redmine_webhook_plugin:rw \
  -v $PWD/.bundle-cache/$VERSION:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:$VERSION \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_result_test.rb -v'

# Full suite (repeat for each version)
VERSION=5.1.0 tools/test/run-test.sh
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
VERSION=7.0.0-dev tools/test/run-test.sh
```

### Commit Message Format
```
feat(d): add <service> <feature>
test(d): add <service> <test coverage>
fix(d): <issue description>
```

---

**End of Implementation Plan**

This plan is ready for delegation to Task Manager agent. All tasks are clearly scoped with acceptance criteria, test counts, and verification steps.
