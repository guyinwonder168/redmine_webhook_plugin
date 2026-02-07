# Last Gap Implementation Plan v2: Redmine Webhook Plugin v1.0.0 (TDD)

**Goal:** Address final functional gaps, PRD alignment, and UI/UX polish using Test-Driven Development.

**Analysis Date:** 2026-02-03
**Status:** Pending implementation
**Supersedes:** `last_gap_implementation_plan.md` (contains test/implementation errors)

---

## Code Review Summary

This plan was reviewed against the actual codebase. Several test and implementation
issues were identified in the original plan and corrected below. See "Analysis Notes"
on each task for details of what was changed.

---

## Task 1: Admin Accessibility & Navigation

**PRD Reference:** FR-23 (Delivery log UI accessible from admin menu), phase-final-impl-plan.md Pending Actions

**Analysis Notes:**
- The endpoints menu already exists in `init.rb:30-31` as `:webhooks`. This task adds
  a **second** admin menu entry for `:webhook_deliveries` pointing to the deliveries controller.
- The test asserts on the new deliveries link (not the existing endpoints link).
- Cross-link from endpoints index to filtered deliveries is valid — `admin_webhook_deliveries_path`
  accepts `endpoint_id` as a query parameter.

### Step 1: Write the failing tests
**Files:**
- `test/functional/admin/webhook_navigation_test.rb`

```ruby
require File.expand_path("../../../test_helper", __dir__)

class Admin::WebhookNavigationTest < ActionController::TestCase
  tests Admin::WebhookEndpointsController
  fixtures :users

  def setup
    @request.session[:user_id] = 1 # admin
  end

  test "admin menu includes Deliveries link" do
    get :index
    assert_select "a.icon-webhook-deliveries", text: /Deliveries/
  end

  test "endpoints index includes link to filtered deliveries" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test", url: "https://example.com"
    )
    get :index
    assert_select "a[href=?]", admin_webhook_deliveries_path(endpoint_id: endpoint.id)
  end
end
```

### Step 2: Run tests to verify failure
Expected: FAIL - Menu link not defined; Cross-link not in view.

### Step 3: Implement
- Modify `init.rb`: Add second menu entry:
  ```ruby
  menu :admin_menu, :webhook_deliveries, { controller: "admin/webhook_deliveries", action: "index" },
       caption: :label_webhook_deliveries, html: { class: "icon icon-webhook-deliveries" },
       after: :webhooks
  ```
- Modify `app/views/admin/webhook_endpoints/index.html.erb`: Add link to filtered deliveries for each endpoint.

### Step 4: Run tests to verify success

---

## Task 2: Global Delivery Pause

**PRD Reference:** FR-22b (Global retry pause)

**Analysis Notes (corrected from original draft):**
- Original test was missing `fixtures :users` declaration — `Endpoint.create!(webhook_user_id: 1)` would fail validation because User with id 1 wouldn't exist.
- Simplified: removed `webhook_user_id` from endpoint creation since it's optional and irrelevant to the pause feature.
- Dispatcher pause test uses minimal event_data — this is correct because the pause check returns early before PayloadBuilder is ever called.
- Sender pause test: implementation MUST add the pause check **before** `mark_delivering!` to keep status as PENDING. The test correctly enforces this constraint.

### Step 1: Write the failing tests
**Files:**
- `test/unit/webhook/global_pause_test.rb`

```ruby
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::GlobalPauseTest < ActiveSupport::TestCase
  fixtures :users, :projects, :trackers, :projects_trackers, :issue_statuses,
           :issues, :enumerations

  def setup
    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Pause Test", url: "https://example.com", enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1]
    )
  end

  test "Dispatcher does not create deliveries when paused" do
    Setting.plugin_redmine_webhook_plugin = { "deliveries_paused" => "1" }

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      project_id: 1,
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1),
      project: Project.find(1)
    }
    deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    assert_empty deliveries, "Should not create deliveries when paused"
  ensure
    Setting.plugin_redmine_webhook_plugin = {
      "execution_mode" => "auto",
      "retention_days_success" => "7",
      "retention_days_failed" => "7",
      "deliveries_paused" => "0"
    }
  end

  test "Sender does not send when paused" do
    Setting.plugin_redmine_webhook_plugin = { "deliveries_paused" => "1" }
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: @endpoint.id, event_id: SecureRandom.uuid,
      event_type: "issue", action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery.reload.status,
      "Delivery should remain PENDING when globally paused"
  ensure
    Setting.plugin_redmine_webhook_plugin = {
      "execution_mode" => "auto",
      "retention_days_success" => "7",
      "retention_days_failed" => "7",
      "deliveries_paused" => "0"
    }
  end
end
```

### Step 2: Run tests to verify failure
Expected: FAIL - Deliveries still created and sent.

### Step 3: Implement
- Modify `app/services/webhook/dispatcher.rb`: Add pause check at the **top** of `self.dispatch`, before endpoint matching:
  ```ruby
  def self.dispatch(event_data)
    return [] if deliveries_paused?
    # ... existing code ...
  end

  def self.deliveries_paused?
    settings = Setting.plugin_redmine_webhook_plugin rescue {}
    settings.is_a?(Hash) && settings["deliveries_paused"] == "1"
  end
  ```
- Modify `app/services/webhook/sender.rb`: Add pause check **before** `mark_delivering!`:
  ```ruby
  def self.send(delivery)
    return if deliveries_paused?
    delivery.mark_delivering!("sender")
    # ... existing code ...
  end

  def self.deliveries_paused?
    settings = Setting.plugin_redmine_webhook_plugin rescue {}
    settings.is_a?(Hash) && settings["deliveries_paused"] == "1"
  end
  ```

### Step 4: Run tests to verify success

---

## Task 3: DB Runner Batch Limits

**PRD Reference:** NFR-7 (DB runner mode: Process max 50 deliveries per rake execution, configurable via BATCH_SIZE env var)

**Analysis Notes (corrected from original draft):**
- **Critical fix:** Rails' `find_each` ignores `.limit()` — it internally uses `find_in_batches`
  which processes ALL records regardless of limit. The implementation MUST use `.limit(n).each`
  instead of `.limit(n).find_each`.
- Test must follow the established rake test pattern from `webhook_rake_test.rb`: use
  `Rake.application = Rake::Application.new`, `Rake::Task.define_task(:environment)`, and
  direct `load` of the rake file.
- Test must clean up `ENV['BATCH_SIZE']` in `ensure` block to avoid leaking into other tests.
- Minitest `stub` on class methods works in Minitest 5+ for `Sender.stub(:send, ...)`.

### Step 1: Write the failing test
**Files:**
- `test/unit/webhook/rake_batch_test.rb`

```ruby
require File.expand_path("../../test_helper", __dir__)
require "rake"

class RedmineWebhookPlugin::Webhook::RakeBatchTest < ActiveSupport::TestCase
  setup do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    plugin_root = File.expand_path("../../..", __dir__)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")

    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all

    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Batch", url: "https://example.com", enabled: true
    )
    60.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        endpoint_id: @endpoint.id, event_id: "e-#{i}", event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
      )
    end
  end

  test "process task respects BATCH_SIZE limit" do
    ENV['BATCH_SIZE'] = '10'
    called_ids = []
    RedmineWebhookPlugin::Webhook::Sender.stub :send, ->(d) { called_ids << d.id } do
      Rake::Task["redmine:webhooks:process"].reenable
      Rake::Task["redmine:webhooks:process"].invoke
    end

    assert_equal 10, called_ids.length, "Should only process BATCH_SIZE deliveries"
  ensure
    ENV.delete('BATCH_SIZE')
  end

  test "process task defaults to 50 batch size" do
    ENV.delete('BATCH_SIZE')
    called_ids = []
    RedmineWebhookPlugin::Webhook::Sender.stub :send, ->(d) { called_ids << d.id } do
      Rake::Task["redmine:webhooks:process"].reenable
      Rake::Task["redmine:webhooks:process"].invoke
    end

    assert_equal 50, called_ids.length, "Should default to 50 deliveries"
  end
end
```

### Step 2: Run test to verify failure
Expected: FAIL - Processes all 60.

### Step 3: Implement
- Modify `lib/tasks/webhook.rake`: Replace `find_each` with `.limit(batch_size).each`:
  ```ruby
  task :process => :environment do
    batch_size = (ENV['BATCH_SIZE'] || 50).to_i
    deliveries = RedmineWebhookPlugin::Webhook::Delivery
      .where(status: [
        RedmineWebhookPlugin::Webhook::Delivery::PENDING,
        RedmineWebhookPlugin::Webhook::Delivery::FAILED
      ])
      .due
      .limit(batch_size)

    deliveries.each do |delivery|
      RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    end
  end
  ```

### Step 4: Run tests to verify success

---

## Task 4: Soft FIFO Stagger — ⏭️ SKIPPED

**PRD Reference:** FR-6b (ActiveJob mode: 500ms stagger delay)

**Status:** SKIPPED — Deferred to v1.1 if monitoring shows need.

**Rationale:**
1. **Incorrect test design:** The original test mocked `DeliveryJob.perform_later(id, {wait: N})`
   but ActiveJob's `wait:` option is not a `perform_later` argument. The correct API is
   `DeliveryJob.set(wait: N).perform_later(id)` which returns a proxy object from `.set()`.
   This makes the test fundamentally untestable with simple mocking.
2. **Marginal benefit:** The PRD itself says "Strict FIFO guarantee deferred to v1.1 if
   monitoring shows need" and describes this as "~95%+ ordering correctness without complex
   distributed locking." The stagger adds complexity for minimal gain.
3. **PRD allows deferral:** FR-6b states "This provides ~95%+ ordering correctness" and
   the receiver guidance is to "Implement 'occurred_at' comparison as defensive measure."
   The payload already includes `occurred_at` and `sequence_number` for receiver-side ordering.

**What stays:**
- `occurred_at` (ISO8601 UTC) and `sequence_number` are included in every payload
- DB runner mode processes in natural database order
- Receiver guidance for timestamp-based conflict resolution documented in PRD Section 10

---

## Task 5: Payload Builder Alignment (last_note)

**PRD Reference:** FR-11a (Journal notes available in full mode as 'last_note' field)

**Analysis Notes (corrected from original draft):**
- The plan originally said to change `assert result.key?(:journal)` — but that assertion
  does **not exist** in the test file. The actual assertions at `payload_builder_test.rb:802-804,821`
  use `result[:journal]` directly.
- **Four** lines need updating (not one), plus the PayloadBuilder source.
- The `issue_patch_test.rb` assertions on `event[:journal]` should NOT change — those test
  the input event_data hash, not the output payload.

### Step 1: Update existing tests
- Modify `test/unit/webhook/payload_builder_test.rb`:
  - Line 802: `assert_not_nil result[:journal]` → `assert_not_nil result[:last_note]`
  - Line 803: `assert_equal journal.id, result[:journal][:id]` → `assert_equal journal.id, result[:last_note][:id]`
  - Line 804: `assert_equal journal.notes, result[:journal][:notes]` → `assert_equal journal.notes, result[:last_note][:notes]`
  - Line 821: `assert_nil result[:journal]` → `assert_nil result[:last_note]`

### Step 2: Run tests to verify failure
Expected: FAIL - result[:last_note] is nil, result[:journal] still present.

### Step 3: Implement
- Modify `app/services/webhook/payload_builder.rb` line 54:
  - Change: `payload[:journal] = serialize_journal(event_data[:journal]) if event_data[:journal]`
  - To: `payload[:last_note] = serialize_journal(event_data[:journal]) if event_data[:journal]`
- Note: The input key `event_data[:journal]` stays as-is — only the output payload key changes.

### Step 4: Run tests to verify success

---

## Task 6: Cross-version verification (Final)

1. Run full suite on all versions:
```bash
VERSION=all tools/test/run-test.sh
```

2. Verify README and CHANGELOG updates.
3. Commit with "v1.0.0 Release Candidate" summary.

---

## Implementation Order & Dependencies

```
Task 1 (Navigation)     — independent
Task 2 (Global Pause)   — independent
Task 3 (Batch Limits)   — independent
Task 4 (FIFO Stagger)   — SKIPPED
Task 5 (last_note)      — independent
Task 6 (Verification)   — depends on Tasks 1-3, 5
```

Tasks 1, 2, 3, and 5 are independent and can be implemented in parallel or any order.

---

## PRD Coverage Checklist

| PRD Requirement | Status | Task |
|----------------|--------|------|
| FR-22b: Global delivery pause | Pending | Task 2 |
| FR-6b: Soft FIFO stagger (ActiveJob) | Deferred to v1.1 | Task 4 (SKIPPED) |
| NFR-7: DB runner batch limits | Pending | Task 3 |
| FR-11a: `last_note` field in payload | Pending | Task 5 |
| Admin menu Deliveries link | Pending | Task 1 |
| Cross-link endpoints → deliveries | Pending | Task 1 |

---

## Changes from Original Plan (`last_gap_implementation_plan.md`)

### Task 1
- Changed test selector from `a.icon-webhook` to `a.icon-webhook-deliveries` to distinguish from existing endpoints menu
- Added `fixtures :users` declaration

### Task 2
- Added `fixtures :users, :projects, ...` declaration
- Removed `webhook_user_id: 1` from endpoint creation (unnecessary)
- Added complete event_data with all required PayloadBuilder fields
- Added `ensure` blocks to reset settings after tests
- Clarified that pause check in Sender must come BEFORE `mark_delivering!`

### Task 3
- **Critical:** Changed implementation from `.limit(n).find_each` to `.limit(n).each` because `find_each` ignores `limit()`
- Changed test pattern to match existing `webhook_rake_test.rb` conventions
- Added `ensure` block to clean up ENV
- Added second test for default batch size

### Task 4
- Marked as SKIPPED with detailed rationale
- Documented what stays (occurred_at, sequence_number in payload)

### Task 5
- Corrected: 4 test lines need updating, not 1
- Specified exact line numbers and changes
- Clarified that `issue_patch_test.rb` assertions should NOT change
