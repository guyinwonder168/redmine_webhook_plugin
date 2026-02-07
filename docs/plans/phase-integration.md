# Integration Phase Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire event capture, payload building, delivery persistence, and delivery execution into a functioning webhook pipeline.

**Architecture:** Dispatcher accepts event data and creates delivery records for matching endpoints. Sender executes HTTP delivery, updates status, and schedules retries. Execution mode selects ActiveJob or DB runner rake task. Delivery processing enforces locks and endpoint/user validation.

**Tech Stack:** Ruby/Rails, ActiveRecord, ActiveJob, Redmine plugin API, Minitest

**Depends on:** Workstreams A, B, C, D complete

## Redmine 7.0+ Compatibility

- Detect native webhooks via `defined?(::Webhook) && ::Webhook < ApplicationRecord`.
- When native exists, disable or bypass native delivery; the plugin remains authoritative.
- Use `RedmineWebhookPlugin::` for plugin service namespaces to avoid conflicts with native `Webhook`.

---

## Testing Environment (Podman)

All tests run inside Podman containers to ensure consistent Ruby/Rails versions. The workspace has three Redmine versions available:

| Version | Directory | Image | Ruby |
|---------|-----------|-------|------|
| 5.1.0 | `.redmine-test/redmine-5.1.0/` | `redmine-dev:5.1.0` | 3.2.2 |
| 5.1.10 | `.redmine-test/redmine-5.1.10/` | `redmine-dev:5.1.10` | 3.2.2 |
| 6.1.0 | `.redmine-test/redmine-6.1.0/` | `redmine-dev:6.1.0` | 3.3.4 |
| 7.0.0-dev | `.redmine-test/redmine-7.0.0-dev/` | `redmine-dev:7.0.0-dev` | 3.3.4 |

> **IMPORTANT:** Every task MUST be verified on ALL FOUR Redmine versions before marking complete.

### Cross-Version Test Pattern

After implementing each task, run the test on all three versions:

```bash
# From /media/eddy/hdd/Project/redmine_webhook_plugin

# 5.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 7.0.0-dev
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-7.0.0-dev:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/7.0.0-dev:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:7.0.0-dev \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'
```

---

## Task 1: Dispatcher Service Skeleton

**Files:**
- Create: `app/services/webhook/dispatcher.rb`
- Test: `test/unit/webhook/dispatcher_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/dispatcher_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DispatcherTest < ActiveSupport::TestCase
  test "Dispatcher responds to dispatch" do
    assert_respond_to RedmineWebhookPlugin::Webhook::Dispatcher, :dispatch
  end

  test "dispatch returns array of deliveries" do
    event_data = { event_type: "issue", action: "created" }
    result = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    assert_kind_of Array, result
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```


Expected: FAIL with uninitialized constant RedmineWebhookPlugin::Webhook::Dispatcher

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/dispatcher.rb
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    def self.dispatch(_event_data)
      []
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 2 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/dispatcher.rb test/unit/webhook/dispatcher_test.rb
git commit -m "feat(integration): add Dispatcher skeleton"
```

---

## Task 2: Dispatcher Filters Endpoints

**Files:**
- Modify: `app/services/webhook/dispatcher.rb`
- Modify: `test/unit/webhook/dispatcher_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/dispatcher_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::DispatcherTest < ActiveSupport::TestCase
  test "dispatch filters endpoints by enabled and matches_event?" do
    endpoint1 = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Enabled", url: "https://a.com", enabled: true)
    endpoint1.events_config = { "issue" => { "created" => true } }
    endpoint1.save!

    endpoint2 = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Disabled", url: "https://b.com", enabled: false)
    endpoint2.events_config = { "issue" => { "created" => true } }
    endpoint2.save!

    endpoint3 = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "NoMatch", url: "https://c.com", enabled: true)
    endpoint3.events_config = { "issue" => { "updated" => true } }
    endpoint3.save!

    event_data = { event_type: "issue", action: "created", project_id: 1 }
    deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    assert_equal 1, deliveries.length
    assert_equal endpoint1.id, deliveries.first.endpoint_id
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```


Expected: FAIL - dispatch still returns empty array

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/dispatcher.rb
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    def self.dispatch(event_data)
      endpoints = RedmineWebhookPlugin::Webhook::Endpoint.enabled
      endpoints = endpoints.select do |endpoint|
        endpoint.matches_event?(event_data[:event_type], event_data[:action], event_data[:project_id])
      end

      endpoints.map { |endpoint| { endpoint_id: endpoint.id } }
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/dispatcher.rb test/unit/webhook/dispatcher_test.rb
git commit -m "feat(integration): filter endpoints by event match"
```

---

## Task 3: Create Delivery Records

**Files:**
- Modify: `app/services/webhook/dispatcher.rb`
- Modify: `test/unit/webhook/dispatcher_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/dispatcher_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::DispatcherTest < ActiveSupport::TestCase
  test "dispatch creates delivery records" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Enabled", url: "https://a.com", enabled: true)
    endpoint.events_config = { "issue" => { "created" => true } }
    endpoint.save!

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1),
      project: Project.find(1),
      project_id: 1
    }

    deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    assert_equal 1, deliveries.length
    delivery = deliveries.first
    assert_equal endpoint.id, delivery.endpoint_id
    assert_equal "pending", delivery.status
    assert_equal event_data[:event_id], delivery.event_id
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```


Expected: FAIL - no RedmineWebhookPlugin::Webhook::Delivery created

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/dispatcher.rb
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    def self.dispatch(event_data)
      endpoints = RedmineWebhookPlugin::Webhook::Endpoint.enabled
      matching = endpoints.select do |endpoint|
        endpoint.matches_event?(event_data[:event_type], event_data[:action], event_data[:project_id])
      end

      matching.map { |endpoint| create_delivery(endpoint, event_data) }
    end

    def self.create_delivery(endpoint, event_data)
      payload = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, endpoint.payload_mode).build

      RedmineWebhookPlugin::Webhook::Delivery.create!(
        endpoint_id: endpoint.id,
        webhook_user_id: endpoint.webhook_user_id,
        event_id: event_data[:event_id],
        event_type: event_data[:event_type],
        action: event_data[:action],
        resource_type: event_data[:resource]&.class&.name,
        resource_id: event_data[:resource]&.id,
        sequence_number: event_data[:sequence_number],
        payload: payload.to_json,
        endpoint_url: endpoint.url,
        retry_policy_snapshot: endpoint.retry_config.to_json,
        status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
      )
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/dispatcher.rb test/unit/webhook/dispatcher_test.rb
git commit -m "feat(integration): create delivery records"
```

---

## Task 4: Execution Mode Detection

**Files:**
- Create: `app/services/webhook/execution_mode.rb`
- Test: `test/unit/webhook/execution_mode_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/execution_mode_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::ExecutionModeTest < ActiveSupport::TestCase
  test "detect returns :activejob when queue adapter present" do
    ActiveJob::Base.queue_adapter = :async
    assert_equal :activejob, RedmineWebhookPlugin::Webhook::ExecutionMode.detect
  end

  test "detect returns :db_runner when no queue adapter" do
    ActiveJob::Base.queue_adapter = :inline
    assert_equal :db_runner, RedmineWebhookPlugin::Webhook::ExecutionMode.detect
  end

  test "detect uses override setting" do
    Setting.plugin_redmine_webhook_plugin = { "execution_mode" => "db_runner" }
    assert_equal :db_runner, RedmineWebhookPlugin::Webhook::ExecutionMode.detect
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/execution_mode_test.rb -v'
```


Expected: FAIL with uninitialized constant RedmineWebhookPlugin::Webhook::ExecutionMode

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/execution_mode.rb
module RedmineWebhookPlugin::Webhook
  class ExecutionMode
    def self.detect
      override = Setting.plugin_redmine_webhook_plugin["execution_mode"] rescue nil
      return override.to_sym if override.present?

      adapter = ActiveJob::Base.queue_adapter
      return :activejob if adapter && adapter.class.name !~ /Inline/

      :db_runner
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/execution_mode_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/execution_mode_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/execution_mode_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/execution_mode.rb test/unit/webhook/execution_mode_test.rb
git commit -m "feat(integration): add execution mode detection"
```

---

## Task 5: Sender Service Skeleton

**Files:**
- Create: `app/services/webhook/sender.rb`
- Test: `test/unit/webhook/sender_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/sender_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::SenderTest < ActiveSupport::TestCase
  test "Sender responds to send" do
    assert_respond_to RedmineWebhookPlugin::Webhook::Sender, :send
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```


Expected: FAIL with uninitialized constant RedmineWebhookPlugin::Webhook::Sender

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/sender.rb
module RedmineWebhookPlugin::Webhook
  class Sender
    def self.send(_delivery)
      nil
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/sender.rb test/unit/webhook/sender_test.rb
git commit -m "feat(integration): add Sender skeleton"
```

---

## Task 6: Sender Delivery Workflow

**Files:**
- Modify: `app/services/webhook/sender.rb`
- Modify: `test/unit/webhook/sender_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/sender_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::SenderTest < ActiveSupport::TestCase
  test "send marks delivery delivering then success" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Send", url: "https://example.com")
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    client = Minitest::Mock.new
    client.expect :post, RedmineWebhookPlugin::Webhook::DeliveryResult.success(http_status: 200, duration_ms: 10), [Hash]

    RedmineWebhookPlugin::Webhook::HttpClient.stub(:new, client) do
      RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    end

    assert_equal RedmineWebhookPlugin::Webhook::Delivery::SUCCESS, delivery.reload.status
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```


Expected: FAIL - send does nothing

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/sender.rb
module RedmineWebhookPlugin::Webhook
  class Sender
    def self.send(delivery)
      delivery.mark_delivering!("sender")

      endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find_by(id: delivery.endpoint_id)
      return if endpoint.nil?

      headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
        event_id: delivery.event_id,
        event_type: delivery.event_type,
        action: delivery.action,
        api_key: nil,
        delivery_id: delivery.id
      )

      client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: endpoint.timeout, ssl_verify: endpoint.ssl_verify)
      result = client.post(url: endpoint.url, payload: delivery.payload || "{}", headers: headers)

      if result.success?
        delivery.mark_success!(result.http_status, result.response_body_excerpt, result.duration_ms)
      else
        delivery.mark_failed!(result.error_code, result.http_status, result.response_body_excerpt)
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 2 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/sender.rb test/unit/webhook/sender_test.rb
git commit -m "feat(integration): add basic Sender workflow"
```

---

## Task 7: Retry Scheduling on Failure

**Files:**
- Modify: `app/services/webhook/sender.rb`
- Modify: `test/unit/webhook/sender_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/sender_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::SenderTest < ActiveSupport::TestCase
  test "retry schedules when retryable failure" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Retry", url: "https://example.com")
    endpoint.retry_config = { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600 }
    endpoint.save!

    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    client = Minitest::Mock.new
    client.expect :post, RedmineWebhookPlugin::Webhook::DeliveryResult.failure(error_code: "connection_timeout", duration_ms: 10), [Hash]

    RedmineWebhookPlugin::Webhook::HttpClient.stub(:new, client) do
      RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    end

    delivery.reload
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::FAILED, delivery.status
    assert_not_nil delivery.scheduled_at
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```


Expected: FAIL - scheduled_at not set

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/sender.rb - add retry policy handling
module RedmineWebhookPlugin::Webhook
  class Sender
    def self.send(delivery)
      delivery.mark_delivering!("sender")

      endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find_by(id: delivery.endpoint_id)
      return if endpoint.nil?

      headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
        event_id: delivery.event_id,
        event_type: delivery.event_type,
        action: delivery.action,
        api_key: nil,
        delivery_id: delivery.id
      )

      client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: endpoint.timeout, ssl_verify: endpoint.ssl_verify)
      result = client.post(url: endpoint.url, payload: delivery.payload || "{}", headers: headers)

      if result.success?
        delivery.mark_success!(result.http_status, result.response_body_excerpt, result.duration_ms)
      else
        delivery.mark_failed!(result.error_code, result.http_status, result.response_body_excerpt)
        schedule_retry(delivery, endpoint, result)
      end
    end

    def self.schedule_retry(delivery, endpoint, result)
      policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(endpoint.retry_config)
      return unless policy.should_retry?(attempt_count: delivery.attempt_count, error_code: result.error_code,
                                         http_status: result.http_status, ssl_verify: endpoint.ssl_verify)

      delivery.update!(scheduled_at: policy.next_retry_at(delivery.attempt_count))
    end

    private_class_method :schedule_retry
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/sender.rb test/unit/webhook/sender_test.rb
git commit -m "feat(integration): schedule retries on failure"
```

---

## Task 8: Delivery Job (ActiveJob)

**Files:**
- Create: `app/jobs/webhook/delivery_job.rb`
- Test: `test/unit/webhook/delivery_job_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/delivery_job_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DeliveryJobTest < ActiveSupport::TestCase
  test "DeliveryJob performs and calls Sender" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Job", url: "https://example.com")
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    called = false
    RedmineWebhookPlugin::Webhook::Sender.stub(:send, ->(_delivery) { called = true }) do
      RedmineWebhookPlugin::Webhook::DeliveryJob.perform_now(delivery.id)
    end

    assert_equal true, called
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_job_test.rb -v'
```


Expected: FAIL with uninitialized constant RedmineWebhookPlugin::Webhook::DeliveryJob

**Step 3: Write minimal implementation**

```ruby
# app/jobs/webhook/delivery_job.rb
module RedmineWebhookPlugin::Webhook
  class DeliveryJob < ActiveJob::Base
    queue_as :default

    def perform(delivery_id)
      delivery = RedmineWebhookPlugin::Webhook::Delivery.find_by(id: delivery_id)
      return if delivery.nil?
      return unless [RedmineWebhookPlugin::Webhook::Delivery::PENDING, RedmineWebhookPlugin::Webhook::Delivery::FAILED].include?(delivery.status)

      RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_job_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_job_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_job_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add app/jobs/webhook/delivery_job.rb test/unit/webhook/delivery_job_test.rb
git commit -m "feat(integration): add DeliveryJob"
```

---

## Task 9: DB Runner Rake Task (Skeleton)

**Files:**
- Create: `lib/tasks/webhook.rake`
- Test: `test/unit/webhook_rake_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook_rake_test.rb
require File.expand_path("../test_helper", __dir__)
require "rake"

class WebhookRakeTest < ActiveSupport::TestCase
  test "webhook rake task is defined" do
    Rake.application.rake_require "tasks/webhook"
    assert Rake::Task.task_defined?("redmine:webhooks:process")
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```


Expected: FAIL - task not defined

**Step 3: Write minimal implementation**

```ruby
# lib/tasks/webhook.rake
namespace :redmine do
  namespace :webhooks do
    desc "Process pending webhook deliveries"
    task :process => :environment do
      # Implementation added in next task
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add lib/tasks/webhook.rake test/unit/webhook_rake_test.rb
git commit -m "feat(integration): add webhook rake task skeleton"
```

---

## Task 10: DB Runner Selection and Locking

**Files:**
- Modify: `lib/tasks/webhook.rake`
- Test: `test/unit/webhook_rake_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook_rake_test.rb - add to existing file
class WebhookRakeTest < ActiveSupport::TestCase
  test "process selects due deliveries" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Runner", url: "https://example.com")

    due = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      scheduled_at: 1.minute.ago
    )

    future = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      scheduled_at: 10.minutes.from_now
    )

    selected = RedmineWebhookPlugin::Webhook::Delivery.pending.due
    assert_includes selected, due
    assert_not_includes selected, future
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```


Expected: FAIL if due scope missing

**Step 3: Write minimal implementation**

```ruby
# lib/tasks/webhook.rake - fill in processing logic
namespace :redmine do
  namespace :webhooks do
    desc "Process pending webhook deliveries"
    task :process => :environment do
      deliveries = RedmineWebhookPlugin::Webhook::Delivery.pending.due
      deliveries.find_each do |delivery|
        RedmineWebhookPlugin::Webhook::Sender.send(delivery)
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 2 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/tasks/webhook.rake test/unit/webhook_rake_test.rb
git commit -m "feat(integration): process due deliveries in rake task"
```

---

## Task 11: Queueing Deliveries Based on Execution Mode

**Files:**
- Modify: `app/services/webhook/dispatcher.rb`
- Modify: `test/unit/webhook/dispatcher_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/dispatcher_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::DispatcherTest < ActiveSupport::TestCase
  test "dispatch enqueues job when execution mode is activejob" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Enabled", url: "https://a.com", enabled: true)
    endpoint.events_config = { "issue" => { "created" => true } }
    endpoint.save!

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1),
      project: Project.find(1),
      project_id: 1
    }

    RedmineWebhookPlugin::Webhook::ExecutionMode.stub(:detect, :activejob) do
      assert_difference "ActiveJob::Base.queue_adapter.enqueued_jobs.size", 1 do
        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```


Expected: FAIL - no job enqueued

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/dispatcher.rb - enqueue based on execution mode
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    def self.dispatch(event_data)
      endpoints = RedmineWebhookPlugin::Webhook::Endpoint.enabled
      matching = endpoints.select do |endpoint|
        endpoint.matches_event?(event_data[:event_type], event_data[:action], event_data[:project_id])
      end

      matching.map do |endpoint|
        delivery = create_delivery(endpoint, event_data)
        enqueue_delivery(delivery)
        delivery
      end
    end

    def self.enqueue_delivery(delivery)
      case RedmineWebhookPlugin::Webhook::ExecutionMode.detect
      when :activejob
        RedmineWebhookPlugin::Webhook::DeliveryJob.perform_later(delivery.id)
      else
        # db_runner does nothing here
      end
    end

    # ... existing create_delivery ...
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/dispatcher_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/dispatcher.rb test/unit/webhook/dispatcher_test.rb
git commit -m "feat(integration): enqueue deliveries based on execution mode"
```

---

## Task 12: User Validation and API Key Resolution

**Files:**
- Modify: `app/services/webhook/sender.rb`
- Modify: `test/unit/webhook/sender_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/sender_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::SenderTest < ActiveSupport::TestCase
  test "send marks failed if webhook_user is invalid" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "InvalidUser", url: "https://example.com", webhook_user_id: 99999)
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    RedmineWebhookPlugin::Webhook::Sender.send(delivery)

    assert_equal RedmineWebhookPlugin::Webhook::Delivery::FAILED, delivery.reload.status
    assert_equal "webhook_user_invalid", delivery.error_code
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```


Expected: FAIL - sender doesn't validate user

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/sender.rb - add user validation
module RedmineWebhookPlugin::Webhook
  class Sender
    def self.send(delivery)
      delivery.mark_delivering!("sender")

      endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find_by(id: delivery.endpoint_id)
      return if endpoint.nil?

      if endpoint.webhook_user_id.present?
        user = User.find_by(id: endpoint.webhook_user_id)
        unless user&.active?
          delivery.mark_failed!("webhook_user_invalid", nil, "Webhook user invalid")
          return
        end
      end

      headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
        event_id: delivery.event_id,
        event_type: delivery.event_type,
        action: delivery.action,
        api_key: nil,
        delivery_id: delivery.id
      )

      client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: endpoint.timeout, ssl_verify: endpoint.ssl_verify)
      result = client.post(url: endpoint.url, payload: delivery.payload || "{}", headers: headers)

      if result.success?
        delivery.mark_success!(result.http_status, result.response_body_excerpt, result.duration_ms)
      else
        delivery.mark_failed!(result.error_code, result.http_status, result.response_body_excerpt)
        schedule_retry(delivery, endpoint, result)
      end
    end

    # ... schedule_retry ...
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/sender.rb test/unit/webhook/sender_test.rb
git commit -m "feat(integration): validate webhook user before sending"
```

---

## Task 13: API Key Fingerprint Recording

**Files:**
- Modify: `app/services/webhook/sender.rb`
- Modify: `test/unit/webhook/sender_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/sender_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::SenderTest < ActiveSupport::TestCase
  test "send records api_key_fingerprint" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Key", url: "https://example.com")
    user = User.find(1)
    endpoint.update!(webhook_user_id: user.id)

    token = Token.create!(user: user, action: "api")

    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    client = Minitest::Mock.new
    client.expect :post, RedmineWebhookPlugin::Webhook::DeliveryResult.success(http_status: 200, duration_ms: 10), [Hash]

    RedmineWebhookPlugin::Webhook::HttpClient.stub(:new, client) do
      RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    end

    assert_equal RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(token.value), delivery.reload.api_key_fingerprint
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```


Expected: FAIL - fingerprint not set

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/sender.rb - add api key handling
module RedmineWebhookPlugin::Webhook
  class Sender
    def self.send(delivery)
      delivery.mark_delivering!("sender")

      endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find_by(id: delivery.endpoint_id)
      return if endpoint.nil?

      api_key = resolve_api_key(endpoint)
      delivery.update!(api_key_fingerprint: RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(api_key))

      headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
        event_id: delivery.event_id,
        event_type: delivery.event_type,
        action: delivery.action,
        api_key: api_key,
        delivery_id: delivery.id
      )

      client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: endpoint.timeout, ssl_verify: endpoint.ssl_verify)
      result = client.post(url: endpoint.url, payload: delivery.payload || "{}", headers: headers)

      if result.success?
        delivery.mark_success!(result.http_status, result.response_body_excerpt, result.duration_ms)
      else
        delivery.mark_failed!(result.error_code, result.http_status, result.response_body_excerpt)
        schedule_retry(delivery, endpoint, result)
      end
    end

    def self.resolve_api_key(endpoint)
      return nil if endpoint.webhook_user_id.blank?

      RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(endpoint.webhook_user_id)
    rescue RedmineWebhookPlugin::Webhook::ApiKeyResolver::RestApiDisabledError
      nil
    end

    # ... schedule_retry ...
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/sender_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/sender.rb test/unit/webhook/sender_test.rb
git commit -m "feat(integration): record api key fingerprint on delivery"
```

---

## Task 14: Run Integration Tests

**Step 1: Run full plugin tests**

Run:
```bash
# Primary version
VERSION=5.1.0 tools/test/run-test.sh

# Also verify on other versions
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
```


Expected: All tests pass

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat(integration): complete webhook delivery pipeline"
```

---

## Acceptance Criteria

- [ ] Dispatcher creates deliveries for matching endpoints
- [ ] Payloads built with PayloadBuilder
- [ ] ActiveJob or DB runner executes deliveries
- [ ] Sender updates status, schedules retries
- [ ] API key resolution and fingerprint recorded
- [ ] DB runner does not double-send
- [ ] All tests pass

---

## Execution Handoff

Plan complete and saved to `docs/plans/phase-integration.md`. Two execution options:

1. Subagent-Driven (this session) - dispatch a fresh subagent per task, review between tasks
2. Parallel Session (separate) - open new session with @superpowers:executing-plans