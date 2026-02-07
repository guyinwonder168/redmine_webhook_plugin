# Workstream C: Payload Builder Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a PayloadBuilder service that serializes Redmine events (issues, time entries) into JSON webhook payloads with support for minimal and full modes, changes tracking, and size enforcement.

**Architecture:** A `RedmineWebhookPlugin::Webhook::PayloadBuilder` service class that takes event data and payload mode as inputs, producing a complete JSON-serializable hash. The builder composes an envelope (metadata), resource data (issue or time_entry), actor/project info, and a changes array with raw/text values. Delete events include a pre-delete snapshot. Payloads exceeding 1MB are gracefully truncated.

**Tech Stack:** Ruby, ActiveRecord (Redmine models), Minitest/ActiveSupport

**Depends on:** P0 complete (RedmineWebhookPlugin::Webhook::Endpoint and RedmineWebhookPlugin::Webhook::Delivery models exist)
**Parallel with:** Workstreams A, B, D

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

## Task 1: Create PayloadBuilder Service Skeleton

**Files:**
- Create: `app/services/webhook/payload_builder.rb`
- Test: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  test "PayloadBuilder class exists under Webhook namespace" do
    assert defined?(RedmineWebhookPlugin::Webhook::PayloadBuilder), "RedmineWebhookPlugin::Webhook::PayloadBuilder should be defined"
  end

  test "initializes with event_data and payload_mode" do
    event_data = { event_type: "issue", action: "created" }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")

    assert_equal event_data, builder.event_data
    assert_equal "minimal", builder.payload_mode
  end

  test "payload_mode defaults to minimal" do
    event_data = { event_type: "issue", action: "created" }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data)

    assert_equal "minimal", builder.payload_mode
  end

  test "SCHEMA_VERSION constant is defined" do
    assert_equal "1.0", RedmineWebhookPlugin::Webhook::PayloadBuilder::SCHEMA_VERSION
  end

  test "build returns a Hash" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")

    result = builder.build
    assert_kind_of Hash, result
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::PayloadBuilder"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/payload_builder.rb
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      {}
    end
  end
end
```

**Step 4: Update init.rb to require the service**

```ruby
# init.rb - add to the to_prepare block
Rails.application.config.to_prepare do
  require_dependency File.expand_path("../app/models/webhook", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/endpoint", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/delivery", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/payload_builder", __FILE__)
end
```

**Step 5: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 7: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb init.rb
git commit -m "feat(ws-c): add PayloadBuilder service skeleton"
```

---

## Task 2: Build Envelope

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build includes envelope fields" do
    event_id = SecureRandom.uuid
    occurred_at = Time.current
    event_data = {
      event_id: event_id,
      event_type: "issue",
      action: "created",
      occurred_at: occurred_at,
      sequence_number: 12345,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_equal event_id, result[:event_id]
    assert_equal "issue", result[:event_type]
    assert_equal "created", result[:action]
    assert_equal occurred_at.utc.iso8601(3), result[:occurred_at]
    assert_equal 12345, result[:sequence_number]
    assert_equal "full", result[:delivery_mode]
    assert_equal "1.0", result[:schema_version]
  end

  test "build envelope handles nil sequence_number" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "time_entry",
      action: "updated",
      occurred_at: Time.current,
      sequence_number: nil,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:sequence_number]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "expected but was nil"

**Step 3: Update implementation**

```ruby
# app/services/webhook/payload_builder.rb
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      build_envelope
    end

    private

    def build_envelope
      {
        event_id: event_data[:event_id],
        event_type: event_data[:event_type],
        action: event_data[:action],
        occurred_at: format_timestamp(event_data[:occurred_at]),
        sequence_number: event_data[:sequence_number],
        delivery_mode: payload_mode,
        schema_version: SCHEMA_VERSION
      }
    end

    def format_timestamp(time)
      return nil if time.nil?
      time.utc.iso8601(3)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 7 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add envelope builder with event metadata"
```

---

## Task 3: Serialize Actor

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build includes actor when present" do
    user = User.find(2) # admin user from fixtures
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: user,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:actor]
    assert_equal user.id, result[:actor][:id]
    assert_equal user.login, result[:actor][:login]
    assert_equal user.name, result[:actor][:name]
  end

  test "build sets actor to nil when not present" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:actor]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "Expected nil to not be nil" or similar

**Step 3: Update implementation**

```ruby
# app/services/webhook/payload_builder.rb
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload
    end

    private

    def build_envelope
      {
        event_id: event_data[:event_id],
        event_type: event_data[:event_type],
        action: event_data[:action],
        occurred_at: format_timestamp(event_data[:occurred_at]),
        sequence_number: event_data[:sequence_number],
        delivery_mode: payload_mode,
        schema_version: SCHEMA_VERSION
      }
    end

    def serialize_actor(user)
      return nil if user.nil?

      {
        id: user.id,
        login: user.login,
        name: user.name
      }
    end

    def format_timestamp(time)
      return nil if time.nil?
      time.utc.iso8601(3)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 9 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add actor serialization"
```

---

## Task 4: Serialize Project

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build includes project when present" do
    project = Project.find(1) # ecookbook from fixtures
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:project]
    assert_equal project.id, result[:project][:id]
    assert_equal project.identifier, result[:project][:identifier]
    assert_equal project.name, result[:project][:name]
  end

  test "build sets project to nil when not present" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:project]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with key :project missing or nil

**Step 3: Update implementation**

```ruby
# app/services/webhook/payload_builder.rb
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload
    end

    private

    def build_envelope
      {
        event_id: event_data[:event_id],
        event_type: event_data[:event_type],
        action: event_data[:action],
        occurred_at: format_timestamp(event_data[:occurred_at]),
        sequence_number: event_data[:sequence_number],
        delivery_mode: payload_mode,
        schema_version: SCHEMA_VERSION
      }
    end

    def serialize_actor(user)
      return nil if user.nil?

      {
        id: user.id,
        login: user.login,
        name: user.name
      }
    end

    def serialize_project(project)
      return nil if project.nil?

      {
        id: project.id,
        identifier: project.identifier,
        name: project.name
      }
    end

    def format_timestamp(time)
      return nil if time.nil?
      time.utc.iso8601(3)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 11 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add project serialization"
```

---

## Task 5: URL Generation Helpers

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  def setup
    @original_host_name = Setting.host_name
    @original_protocol = Setting.protocol
    Setting.host_name = "redmine.example.com"
    Setting.protocol = "https"
  end

  def teardown
    Setting.host_name = @original_host_name
    Setting.protocol = @original_protocol
  end

  test "issue_web_url generates correct URL" do
    issue = Issue.find(1) # from fixtures
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    url = builder.send(:issue_web_url, issue)
    assert_equal "https://redmine.example.com/issues/#{issue.id}", url
  end

  test "issue_api_url generates correct URL" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    url = builder.send(:issue_api_url, issue)
    assert_equal "https://redmine.example.com/issues/#{issue.id}.json", url
  end

  test "time_entry_web_url generates correct URL" do
    time_entry = TimeEntry.find(1) # from fixtures
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    url = builder.send(:time_entry_web_url, time_entry)
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}", url
  end

  test "time_entry_api_url generates correct URL" do
    time_entry = TimeEntry.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    url = builder.send(:time_entry_api_url, time_entry)
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}.json", url
  end

  test "base_url uses Setting.protocol and Setting.host_name" do
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    assert_equal "https://redmine.example.com", builder.send(:base_url)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `issue_web_url'"

**Step 3: Add URL helpers**

```ruby
# app/services/webhook/payload_builder.rb - add to private section
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    private

    # ... existing private methods ...

    def base_url
      "#{Setting.protocol}://#{Setting.host_name}"
    end

    def issue_web_url(issue)
      "#{base_url}/issues/#{issue.id}"
    end

    def issue_api_url(issue)
      "#{base_url}/issues/#{issue.id}.json"
    end

    def time_entry_web_url(time_entry)
      "#{base_url}/time_entries/#{time_entry.id}"
    end

    def time_entry_api_url(time_entry)
      "#{base_url}/time_entries/#{time_entry.id}.json"
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 16 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add URL generation helpers"
```

---

## Task 6: Issue Minimal Serialization

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "serialize_issue_minimal includes id, url, api_url, and tracker" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:serialize_issue_minimal, issue)

    assert_equal issue.id, result[:id]
    assert_equal "https://redmine.example.com/issues/#{issue.id}", result[:url]
    assert_equal "https://redmine.example.com/issues/#{issue.id}.json", result[:api_url]
    assert_equal issue.tracker.id, result[:tracker][:id]
    assert_equal issue.tracker.name, result[:tracker][:name]
  end

  test "build includes issue data for issue events in minimal mode" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:issue]
    assert_equal issue.id, result[:issue][:id]
    assert_not_nil result[:issue][:tracker]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `serialize_issue_minimal'"

**Step 3: Add issue minimal serialization**

```ruby
# app/services/webhook/payload_builder.rb
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload.merge!(build_resource_data)
      payload
    end

    private

    def build_envelope
      {
        event_id: event_data[:event_id],
        event_type: event_data[:event_type],
        action: event_data[:action],
        occurred_at: format_timestamp(event_data[:occurred_at]),
        sequence_number: event_data[:sequence_number],
        delivery_mode: payload_mode,
        schema_version: SCHEMA_VERSION
      }
    end

    def build_resource_data
      case event_data[:event_type]
      when "issue"
        build_issue_data
      when "time_entry"
        build_time_entry_data
      else
        {}
      end
    end

    def build_issue_data
      resource = event_data[:resource]
      return {} if resource.nil?

      { issue: serialize_issue_minimal(resource) }
    end

    def build_time_entry_data
      {}
    end

    def serialize_issue_minimal(issue)
      {
        id: issue.id,
        url: issue_web_url(issue),
        api_url: issue_api_url(issue),
        tracker: {
          id: issue.tracker.id,
          name: issue.tracker.name
        }
      }
    end

    def serialize_actor(user)
      return nil if user.nil?

      {
        id: user.id,
        login: user.login,
        name: user.name
      }
    end

    def serialize_project(project)
      return nil if project.nil?

      {
        id: project.id,
        identifier: project.identifier,
        name: project.name
      }
    end

    def format_timestamp(time)
      return nil if time.nil?
      time.utc.iso8601(3)
    end

    def base_url
      "#{Setting.protocol}://#{Setting.host_name}"
    end

    def issue_web_url(issue)
      "#{base_url}/issues/#{issue.id}"
    end

    def issue_api_url(issue)
      "#{base_url}/issues/#{issue.id}.json"
    end

    def time_entry_web_url(time_entry)
      "#{base_url}/time_entries/#{time_entry.id}"
    end

    def time_entry_api_url(time_entry)
      "#{base_url}/time_entries/#{time_entry.id}.json"
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 18 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add issue minimal serialization"
```

---

## Task 7: Issue Full Serialization

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "serialize_issue_full includes all minimal fields plus extended data" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")

    result = builder.send(:serialize_issue_full, issue)

    # Minimal fields
    assert_equal issue.id, result[:id]
    assert_not_nil result[:url]
    assert_not_nil result[:api_url]
    assert_not_nil result[:tracker]

    # Extended fields
    assert_equal issue.subject, result[:subject]
    assert_equal issue.description, result[:description]

    assert_equal issue.status.id, result[:status][:id]
    assert_equal issue.status.name, result[:status][:name]

    assert_equal issue.priority.id, result[:priority][:id]
    assert_equal issue.priority.name, result[:priority][:name]

    assert_equal issue.author.id, result[:author][:id]
    assert_equal issue.author.login, result[:author][:login]
    assert_equal issue.author.name, result[:author][:name]

    assert_equal issue.start_date&.iso8601, result[:start_date]
    assert_equal issue.due_date&.iso8601, result[:due_date]
    assert_equal issue.created_on.utc.iso8601(3), result[:created_on]
    assert_equal issue.updated_on.utc.iso8601(3), result[:updated_on]

    assert_equal issue.done_ratio, result[:done_ratio]
    assert_equal issue.estimated_hours, result[:estimated_hours]
  end

  test "serialize_issue_full includes assigned_to when present" do
    issue = Issue.find(2) # has assigned_to in fixtures
    issue.assigned_to ||= User.find(2) # ensure assigned
    issue.save! if issue.changed?

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")
    result = builder.send(:serialize_issue_full, issue)

    if issue.assigned_to
      assert_not_nil result[:assigned_to]
      assert_equal issue.assigned_to.id, result[:assigned_to][:id]
    end
  end

  test "serialize_issue_full sets assigned_to to nil when not present" do
    issue = Issue.new(
      project: Project.find(1),
      tracker: Tracker.find(1),
      subject: "Test",
      author: User.find(2),
      status: IssueStatus.find(1),
      priority: IssuePriority.find(4)
    )
    issue.save!

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")
    result = builder.send(:serialize_issue_full, issue)

    assert_nil result[:assigned_to]
  end

  test "serialize_issue_full includes parent_issue when present" do
    parent = Issue.find(1)
    child = Issue.new(
      project: parent.project,
      tracker: parent.tracker,
      subject: "Child issue",
      author: User.find(2),
      status: IssueStatus.find(1),
      priority: IssuePriority.find(4),
      parent_issue_id: parent.id
    )
    child.save!

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")
    result = builder.send(:serialize_issue_full, child)

    assert_not_nil result[:parent_issue]
    assert_equal parent.id, result[:parent_issue][:id]
    assert_equal parent.subject, result[:parent_issue][:subject]
  end

  test "serialize_issue_full includes custom_fields array" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")
    result = builder.send(:serialize_issue_full, issue)

    assert_kind_of Array, result[:custom_fields]
  end

  test "build includes issue_full for full mode" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:issue]
    assert_equal issue.subject, result[:issue][:subject]
    assert_not_nil result[:issue][:status]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `serialize_issue_full'"

**Step 3: Add issue full serialization**

```ruby
# app/services/webhook/payload_builder.rb - update build_issue_data and add serialize_issue_full
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    private

    # ... existing methods ...

    def build_issue_data
      resource = event_data[:resource]
      return {} if resource.nil?

      issue_data = full_mode? ? serialize_issue_full(resource) : serialize_issue_minimal(resource)
      { issue: issue_data }
    end

    def full_mode?
      payload_mode == "full"
    end

    def serialize_issue_minimal(issue)
      {
        id: issue.id,
        url: issue_web_url(issue),
        api_url: issue_api_url(issue),
        tracker: {
          id: issue.tracker.id,
          name: issue.tracker.name
        }
      }
    end

    def serialize_issue_full(issue)
      minimal = serialize_issue_minimal(issue)
      minimal.merge(
        subject: issue.subject,
        description: issue.description,
        status: {
          id: issue.status.id,
          name: issue.status.name
        },
        priority: {
          id: issue.priority.id,
          name: issue.priority.name
        },
        assigned_to: serialize_actor(issue.assigned_to),
        author: serialize_actor(issue.author),
        start_date: issue.start_date&.iso8601,
        due_date: issue.due_date&.iso8601,
        created_on: format_timestamp(issue.created_on),
        updated_on: format_timestamp(issue.updated_on),
        done_ratio: issue.done_ratio,
        estimated_hours: issue.estimated_hours,
        parent_issue: serialize_parent_issue(issue.parent),
        custom_fields: serialize_custom_fields(issue)
      )
    end

    def serialize_parent_issue(parent)
      return nil if parent.nil?

      {
        id: parent.id,
        subject: parent.subject
      }
    end

    def serialize_custom_fields(resource)
      return [] unless resource.respond_to?(:custom_field_values)

      resource.custom_field_values.map do |cfv|
        {
          id: cfv.custom_field.id,
          name: cfv.custom_field.name,
          value: cfv.value
        }
      end
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 24 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add issue full serialization with all fields"
```

---

## Task 8: TimeEntry Minimal Serialization

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "serialize_time_entry_minimal includes id, url, api_url, and issue" do
    time_entry = TimeEntry.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:serialize_time_entry_minimal, time_entry)

    assert_equal time_entry.id, result[:id]
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}", result[:url]
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}.json", result[:api_url]

    if time_entry.issue
      assert_not_nil result[:issue]
      assert_equal time_entry.issue.id, result[:issue][:id]
      assert_equal time_entry.issue.subject, result[:issue][:subject]
    else
      assert_nil result[:issue]
    end
  end

  test "serialize_time_entry_minimal handles nil issue" do
    time_entry = TimeEntry.new(
      project: Project.find(1),
      user: User.find(2),
      hours: 1.5,
      activity: TimeEntryActivity.first,
      spent_on: Date.today
    )
    time_entry.save!

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")
    result = builder.send(:serialize_time_entry_minimal, time_entry)

    assert_nil result[:issue]
  end

  test "build includes time_entry data for time_entry events in minimal mode" do
    time_entry = TimeEntry.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "time_entry",
      action: "created",
      occurred_at: Time.current,
      resource: time_entry,
      actor: time_entry.user,
      project: time_entry.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:time_entry]
    assert_equal time_entry.id, result[:time_entry][:id]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `serialize_time_entry_minimal'"

**Step 3: Add time entry minimal serialization**

```ruby
# app/services/webhook/payload_builder.rb - update build_time_entry_data and add serialize_time_entry_minimal
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    private

    # ... existing methods ...

    def build_time_entry_data
      resource = event_data[:resource]
      return {} if resource.nil?

      { time_entry: serialize_time_entry_minimal(resource) }
    end

    def serialize_time_entry_minimal(time_entry)
      {
        id: time_entry.id,
        url: time_entry_web_url(time_entry),
        api_url: time_entry_api_url(time_entry),
        issue: serialize_time_entry_issue_minimal(time_entry.issue)
      }
    end

    def serialize_time_entry_issue_minimal(issue)
      return nil if issue.nil?

      {
        id: issue.id,
        subject: issue.subject
      }
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 27 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add time entry minimal serialization"
```

---

## Task 9: TimeEntry Full Serialization

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "serialize_time_entry_full includes all minimal fields plus extended data" do
    time_entry = TimeEntry.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")

    result = builder.send(:serialize_time_entry_full, time_entry)

    # Minimal fields
    assert_equal time_entry.id, result[:id]
    assert_not_nil result[:url]
    assert_not_nil result[:api_url]

    # Extended fields
    assert_equal time_entry.hours, result[:hours]
    assert_equal time_entry.spent_on.iso8601, result[:spent_on]
    assert_equal time_entry.comments, result[:comments]

    assert_not_nil result[:activity]
    assert_equal time_entry.activity.id, result[:activity][:id]
    assert_equal time_entry.activity.name, result[:activity][:name]

    assert_not_nil result[:user]
    assert_equal time_entry.user.id, result[:user][:id]
    assert_equal time_entry.user.login, result[:user][:login]
    assert_equal time_entry.user.name, result[:user][:name]

    assert_kind_of Array, result[:custom_fields]
  end

  test "serialize_time_entry_full includes expanded issue with tracker and project" do
    time_entry = TimeEntry.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")

    result = builder.send(:serialize_time_entry_full, time_entry)

    if time_entry.issue
      assert_not_nil result[:issue]
      assert_equal time_entry.issue.id, result[:issue][:id]
      assert_equal time_entry.issue.subject, result[:issue][:subject]
      assert_not_nil result[:issue][:tracker]
      assert_not_nil result[:issue][:project]
    end
  end

  test "build includes time_entry full data for full mode" do
    time_entry = TimeEntry.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "time_entry",
      action: "created",
      occurred_at: Time.current,
      resource: time_entry,
      actor: time_entry.user,
      project: time_entry.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:time_entry]
    assert_not_nil result[:time_entry][:hours]
    assert_not_nil result[:time_entry][:activity]
    assert_not_nil result[:time_entry][:user]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `serialize_time_entry_full'"

**Step 3: Add time entry full serialization**

```ruby
# app/services/webhook/payload_builder.rb - update build_time_entry_data and add serialize_time_entry_full
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    private

    # ... existing methods ...

    def build_time_entry_data
      resource = event_data[:resource]
      return {} if resource.nil?

      time_entry_data = full_mode? ? serialize_time_entry_full(resource) : serialize_time_entry_minimal(resource)
      { time_entry: time_entry_data }
    end

    def serialize_time_entry_minimal(time_entry)
      {
        id: time_entry.id,
        url: time_entry_web_url(time_entry),
        api_url: time_entry_api_url(time_entry),
        issue: serialize_time_entry_issue_minimal(time_entry.issue)
      }
    end

    def serialize_time_entry_full(time_entry)
      {
        id: time_entry.id,
        url: time_entry_web_url(time_entry),
        api_url: time_entry_api_url(time_entry),
        hours: time_entry.hours,
        spent_on: time_entry.spent_on&.iso8601,
        comments: time_entry.comments,
        activity: {
          id: time_entry.activity.id,
          name: time_entry.activity.name
        },
        user: serialize_actor(time_entry.user),
        issue: serialize_time_entry_issue_full(time_entry.issue),
        custom_fields: serialize_custom_fields(time_entry)
      }
    end

    def serialize_time_entry_issue_minimal(issue)
      return nil if issue.nil?

      {
        id: issue.id,
        subject: issue.subject
      }
    end

    def serialize_time_entry_issue_full(issue)
      return nil if issue.nil?

      {
        id: issue.id,
        subject: issue.subject,
        tracker: {
          id: issue.tracker.id,
          name: issue.tracker.name
        },
        project: {
          id: issue.project.id,
          identifier: issue.project.identifier,
          name: issue.project.name
        }
      }
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 30 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add time entry full serialization"
```

---

## Task 10: Value Resolution Helper

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "resolve_value returns raw and text for status_id" do
    issue = Issue.find(1)
    status = IssueStatus.find(2)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "status_id", status.id, issue)

    assert_equal status.id, result[:raw]
    assert_equal status.name, result[:text]
  end

  test "resolve_value returns raw and text for priority_id" do
    issue = Issue.find(1)
    priority = IssuePriority.find(5)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "priority_id", priority.id, issue)

    assert_equal priority.id, result[:raw]
    assert_equal priority.name, result[:text]
  end

  test "resolve_value returns raw and text for assigned_to_id" do
    issue = Issue.find(1)
    user = User.find(2)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "assigned_to_id", user.id, issue)

    assert_equal user.id, result[:raw]
    assert_equal user.name, result[:text]
  end

  test "resolve_value returns raw and text for category_id" do
    issue = Issue.find(1)
    category = IssueCategory.first
    skip "No categories in fixtures" unless category

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")
    result = builder.send(:resolve_value, "category_id", category.id, issue)

    assert_equal category.id, result[:raw]
    assert_equal category.name, result[:text]
  end

  test "resolve_value returns raw and text for fixed_version_id" do
    version = Version.first
    skip "No versions in fixtures" unless version

    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")
    result = builder.send(:resolve_value, "fixed_version_id", version.id, issue)

    assert_equal version.id, result[:raw]
    assert_equal version.name, result[:text]
  end

  test "resolve_value returns raw and text for activity_id" do
    activity = TimeEntryActivity.first
    time_entry = TimeEntry.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "activity_id", activity.id, time_entry)

    assert_equal activity.id, result[:raw]
    assert_equal activity.name, result[:text]
  end

  test "resolve_value handles nil gracefully" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "status_id", nil, issue)

    assert_nil result[:raw]
    assert_nil result[:text]
  end

  test "resolve_value returns raw only for unknown fields" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "subject", "Test Subject", issue)

    assert_equal "Test Subject", result[:raw]
    assert_equal "Test Subject", result[:text]
  end

  test "resolve_value handles missing record gracefully" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:resolve_value, "status_id", 99999, issue)

    assert_equal 99999, result[:raw]
    assert_nil result[:text]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `resolve_value'"

**Step 3: Add value resolution helper**

```ruby
# app/services/webhook/payload_builder.rb - add resolve_value method
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    private

    # ... existing methods ...

    def resolve_value(field, raw_value, resource)
      return { raw: nil, text: nil } if raw_value.nil?

      text_value = case field.to_s
                   when "status_id"
                     IssueStatus.find_by(id: raw_value)&.name
                   when "priority_id"
                     IssuePriority.find_by(id: raw_value)&.name
                   when "assigned_to_id", "author_id", "user_id"
                     User.find_by(id: raw_value)&.name
                   when "category_id"
                     IssueCategory.find_by(id: raw_value)&.name
                   when "fixed_version_id"
                     Version.find_by(id: raw_value)&.name
                   when "activity_id"
                     TimeEntryActivity.find_by(id: raw_value)&.name
                   when "tracker_id"
                     Tracker.find_by(id: raw_value)&.name
                   when "project_id"
                     Project.find_by(id: raw_value)&.name
                   else
                     raw_value
                   end

      { raw: raw_value, text: text_value }
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 39 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add value resolution helper for raw/text conversion"
```

---

## Task 11: Changes Array Builder

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build_changes creates changes array from saved_changes" do
    issue = Issue.find(1)
    saved_changes = {
      "status_id" => [1, 2],
      "subject" => ["Old subject", "New subject"],
      "updated_on" => [1.day.ago, Time.current]
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:build_changes, saved_changes, issue)

    assert_kind_of Array, result

    # Should skip updated_on
    assert_not result.any? { |c| c[:field] == "updated_on" }

    # Should include status_id
    status_change = result.find { |c| c[:field] == "status_id" }
    assert_not_nil status_change
    assert_equal "attribute", status_change[:kind]
    assert_equal 1, status_change[:old][:raw]
    assert_equal 2, status_change[:new][:raw]

    # Should include subject
    subject_change = result.find { |c| c[:field] == "subject" }
    assert_not_nil subject_change
    assert_equal "Old subject", subject_change[:old][:raw]
    assert_equal "New subject", subject_change[:new][:raw]
  end

  test "build_changes skips non-tracked attributes" do
    issue = Issue.find(1)
    saved_changes = {
      "updated_on" => [1.day.ago, Time.current],
      "created_on" => [1.day.ago, Time.current],
      "lock_version" => [1, 2],
      "lft" => [1, 2],
      "rgt" => [3, 4]
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:build_changes, saved_changes, issue)

    assert_empty result
  end

  test "build includes changes for update action" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "updated",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project,
      saved_changes: {
        "status_id" => [1, 2],
        "subject" => ["Old", "New"]
      }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:changes]
    assert_kind_of Array, result[:changes]
    assert result[:changes].length >= 2
  end

  test "build does not include changes for created action" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:changes]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `build_changes'"

**Step 3: Add changes array builder**

```ruby
# app/services/webhook/payload_builder.rb - add build_changes and update build method
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze

    SKIP_ATTRIBUTES = %w[
      updated_on created_on lock_version lft rgt root_id
      updated_at created_at
    ].freeze

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload.merge!(build_resource_data)
      payload[:changes] = build_changes_for_event if update_action?
      payload
    end

    private

    def update_action?
      event_data[:action] == "updated"
    end

    def build_changes_for_event
      saved_changes = event_data[:saved_changes]
      return [] if saved_changes.nil? || saved_changes.empty?

      build_changes(saved_changes, event_data[:resource])
    end

    def build_changes(saved_changes, resource)
      saved_changes.each_with_object([]) do |(field, values), changes|
        next if SKIP_ATTRIBUTES.include?(field.to_s)

        old_value, new_value = values
        changes << {
          field: field,
          kind: "attribute",
          old: resolve_value(field, old_value, resource),
          new: resolve_value(field, new_value, resource)
        }
      end
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 43 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add changes array builder for update events"
```

---

## Task 12: Custom Field Changes

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build_custom_field_changes creates changes for custom fields" do
    custom_field_changes = {
      "2" => { old: "old value", new: "new value", name: "Database" }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:build_custom_field_changes, custom_field_changes)

    assert_kind_of Array, result
    assert_equal 1, result.length

    cf_change = result.first
    assert_equal "custom_field:2", cf_change[:field]
    assert_equal "custom_field", cf_change[:kind]
    assert_equal "Database", cf_change[:name]
    assert_equal "old value", cf_change[:old][:raw]
    assert_equal "old value", cf_change[:old][:text]
    assert_equal "new value", cf_change[:new][:raw]
    assert_equal "new value", cf_change[:new][:text]
  end

  test "build_custom_field_changes handles empty changes" do
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:build_custom_field_changes, {})
    assert_empty result

    result = builder.send(:build_custom_field_changes, nil)
    assert_empty result
  end

  test "build includes custom field changes in changes array" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "updated",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project,
      saved_changes: { "status_id" => [1, 2] },
      custom_field_changes: {
        "2" => { old: "MySQL", new: "PostgreSQL", name: "Database" }
      }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    cf_change = result[:changes].find { |c| c[:kind] == "custom_field" }
    assert_not_nil cf_change
    assert_equal "custom_field:2", cf_change[:field]
    assert_equal "Database", cf_change[:name]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `build_custom_field_changes'"

**Step 3: Add custom field changes builder**

```ruby
# app/services/webhook/payload_builder.rb - add build_custom_field_changes and update build_changes_for_event
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    private

    def build_changes_for_event
      saved_changes = event_data[:saved_changes]
      custom_field_changes = event_data[:custom_field_changes]

      changes = []
      changes.concat(build_changes(saved_changes, event_data[:resource])) if saved_changes.present?
      changes.concat(build_custom_field_changes(custom_field_changes)) if custom_field_changes.present?
      changes
    end

    def build_custom_field_changes(custom_field_changes)
      return [] if custom_field_changes.nil? || custom_field_changes.empty?

      custom_field_changes.map do |cf_id, change_data|
        {
          field: "custom_field:#{cf_id}",
          kind: "custom_field",
          name: change_data[:name],
          old: { raw: change_data[:old], text: change_data[:old] },
          new: { raw: change_data[:new], text: change_data[:new] }
        }
      end
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 46 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add custom field changes support"
```

---

## Task 13: Delete Snapshot Builder

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build_delete_snapshot creates snapshot from captured attributes" do
    snapshot = {
      id: 123,
      subject: "Deleted issue",
      tracker_id: 1,
      tracker_name: "Bug",
      project_id: 1,
      project_identifier: "ecookbook",
      project_name: "eCookbook",
      status_id: 1,
      status_name: "New",
      priority_id: 4,
      priority_name: "Normal",
      author_id: 2,
      author_login: "jsmith",
      author_name: "John Smith"
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")

    result = builder.send(:build_delete_snapshot, snapshot, "issue")

    assert_equal "pre_delete", result[:snapshot_type]
    assert_equal 123, result[:id]
    assert_equal "Deleted issue", result[:subject]
    assert_equal({ id: 1, name: "Bug" }, result[:tracker])
    assert_equal({ id: 1, name: "New" }, result[:status])
    assert_equal({ id: 4, name: "Normal" }, result[:priority])
  end

  test "build includes delete snapshot for deleted action" do
    snapshot = {
      id: 999,
      subject: "Issue to delete",
      tracker_id: 1,
      tracker_name: "Bug",
      project_id: 1,
      project_identifier: "ecookbook",
      project_name: "eCookbook",
      status_id: 1,
      status_name: "New",
      priority_id: 4,
      priority_name: "Normal",
      author_id: 2,
      author_login: "admin",
      author_name: "Admin"
    }
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "deleted",
      occurred_at: Time.current,
      resource: nil,
      resource_snapshot: snapshot,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:issue]
    assert_equal "pre_delete", result[:issue][:snapshot_type]
    assert_equal 999, result[:issue][:id]
  end

  test "build_delete_snapshot for time_entry" do
    snapshot = {
      id: 456,
      hours: 2.5,
      spent_on: Date.today.iso8601,
      comments: "Work done",
      activity_id: 9,
      activity_name: "Development",
      user_id: 2,
      user_login: "jsmith",
      user_name: "John Smith",
      project_id: 1,
      project_identifier: "ecookbook",
      project_name: "eCookbook",
      issue_id: 1,
      issue_subject: "Parent issue"
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "full")

    result = builder.send(:build_delete_snapshot, snapshot, "time_entry")

    assert_equal "pre_delete", result[:snapshot_type]
    assert_equal 456, result[:id]
    assert_equal 2.5, result[:hours]
    assert_equal({ id: 9, name: "Development" }, result[:activity])
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "undefined method `build_delete_snapshot'"

**Step 3: Add delete snapshot builder**

```ruby
# app/services/webhook/payload_builder.rb - add delete snapshot support
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload.merge!(build_resource_data)
      payload[:changes] = build_changes_for_event if update_action?
      payload
    end

    private

    def build_resource_data
      case event_data[:event_type]
      when "issue"
        build_issue_data
      when "time_entry"
        build_time_entry_data
      else
        {}
      end
    end

    def build_issue_data
      if delete_action?
        snapshot = event_data[:resource_snapshot]
        return {} if snapshot.nil?
        { issue: build_delete_snapshot(snapshot, "issue") }
      else
        resource = event_data[:resource]
        return {} if resource.nil?
        issue_data = full_mode? ? serialize_issue_full(resource) : serialize_issue_minimal(resource)
        { issue: issue_data }
      end
    end

    def build_time_entry_data
      if delete_action?
        snapshot = event_data[:resource_snapshot]
        return {} if snapshot.nil?
        { time_entry: build_delete_snapshot(snapshot, "time_entry") }
      else
        resource = event_data[:resource]
        return {} if resource.nil?
        time_entry_data = full_mode? ? serialize_time_entry_full(resource) : serialize_time_entry_minimal(resource)
        { time_entry: time_entry_data }
      end
    end

    def delete_action?
      event_data[:action] == "deleted"
    end

    def build_delete_snapshot(snapshot, resource_type)
      case resource_type
      when "issue"
        build_issue_delete_snapshot(snapshot)
      when "time_entry"
        build_time_entry_delete_snapshot(snapshot)
      else
        { snapshot_type: "pre_delete" }
      end
    end

    def build_issue_delete_snapshot(snapshot)
      {
        snapshot_type: "pre_delete",
        id: snapshot[:id],
        subject: snapshot[:subject],
        description: snapshot[:description],
        tracker: { id: snapshot[:tracker_id], name: snapshot[:tracker_name] },
        status: { id: snapshot[:status_id], name: snapshot[:status_name] },
        priority: { id: snapshot[:priority_id], name: snapshot[:priority_name] },
        author: {
          id: snapshot[:author_id],
          login: snapshot[:author_login],
          name: snapshot[:author_name]
        },
        assigned_to: snapshot[:assigned_to_id] ? {
          id: snapshot[:assigned_to_id],
          login: snapshot[:assigned_to_login],
          name: snapshot[:assigned_to_name]
        } : nil,
        project: {
          id: snapshot[:project_id],
          identifier: snapshot[:project_identifier],
          name: snapshot[:project_name]
        },
        start_date: snapshot[:start_date],
        due_date: snapshot[:due_date],
        done_ratio: snapshot[:done_ratio],
        estimated_hours: snapshot[:estimated_hours]
      }
    end

    def build_time_entry_delete_snapshot(snapshot)
      {
        snapshot_type: "pre_delete",
        id: snapshot[:id],
        hours: snapshot[:hours],
        spent_on: snapshot[:spent_on],
        comments: snapshot[:comments],
        activity: { id: snapshot[:activity_id], name: snapshot[:activity_name] },
        user: {
          id: snapshot[:user_id],
          login: snapshot[:user_login],
          name: snapshot[:user_name]
        },
        project: {
          id: snapshot[:project_id],
          identifier: snapshot[:project_identifier],
          name: snapshot[:project_name]
        },
        issue: snapshot[:issue_id] ? {
          id: snapshot[:issue_id],
          subject: snapshot[:issue_subject]
        } : nil
      }
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 49 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add delete snapshot builder for pre-delete data capture"
```

---

## Task 14: Payload Size Enforcement

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "MAX_PAYLOAD_SIZE constant is 1MB" do
    assert_equal 1_048_576, RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_PAYLOAD_SIZE
  end

  test "MAX_CHANGES constant is 100" do
    assert_equal 100, RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_CHANGES
  end

  test "enforce_size_limit does nothing when under limit" do
    payload = { event_id: "123", changes: [{ field: "a" }] }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:enforce_size_limit, payload)

    assert_equal payload, result
    assert_nil result[:changes_truncated]
    assert_nil result[:custom_fields_excluded]
  end

  test "enforce_size_limit truncates changes when over limit" do
    large_changes = 150.times.map { |i| { field: "field_#{i}", old: "a" * 1000, new: "b" * 1000 } }
    payload = {
      event_id: "123",
      changes: large_changes,
      issue: { custom_fields: [] }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:enforce_size_limit, payload)

    assert_equal 100, result[:changes].length
    assert_equal true, result[:changes_truncated]
  end

  test "enforce_size_limit excludes custom_fields when still over limit" do
    # Create a payload that's over 1MB even after truncating changes
    huge_custom_fields = 500.times.map { |i| { id: i, value: "x" * 2000 } }
    payload = {
      event_id: "123",
      changes: [],
      issue: {
        id: 1,
        custom_fields: huge_custom_fields
      }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    result = builder.send(:enforce_size_limit, payload)

    assert_empty result[:issue][:custom_fields]
    assert_equal true, result[:custom_fields_excluded]
  end

  test "enforce_size_limit raises error when still over limit after all reductions" do
    # Create impossibly large core data
    huge_subject = "x" * 2_000_000
    payload = {
      event_id: "123",
      issue: {
        id: 1,
        subject: huge_subject,
        custom_fields: []
      },
      changes: []
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({}, "minimal")

    error = assert_raises(RedmineWebhookPlugin::Webhook::PayloadBuilder::PayloadTooLargeError) do
      builder.send(:enforce_size_limit, payload)
    end

    assert_match(/exceeds maximum size/, error.message)
  end

  test "build applies size enforcement" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    # Should not raise and should be under 1MB
    assert result.to_json.bytesize < RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_PAYLOAD_SIZE
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL with "uninitialized constant MAX_PAYLOAD_SIZE"

**Step 3: Add payload size enforcement**

```ruby
# app/services/webhook/payload_builder.rb - add size enforcement
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze
    MAX_PAYLOAD_SIZE = 1_048_576  # 1MB
    MAX_CHANGES = 100

    SKIP_ATTRIBUTES = %w[
      updated_on created_on lock_version lft rgt root_id
      updated_at created_at
    ].freeze

    class PayloadTooLargeError < StandardError; end

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      @event_data = event_data
      @payload_mode = payload_mode
    end

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload.merge!(build_resource_data)
      payload[:changes] = build_changes_for_event if update_action?
      enforce_size_limit(payload)
    end

    private

    def enforce_size_limit(payload)
      return payload if payload_size(payload) <= MAX_PAYLOAD_SIZE

      # Step 1: Truncate changes to MAX_CHANGES
      if payload[:changes].is_a?(Array) && payload[:changes].length > MAX_CHANGES
        payload[:changes] = payload[:changes].last(MAX_CHANGES)
        payload[:changes_truncated] = true
      end

      return payload if payload_size(payload) <= MAX_PAYLOAD_SIZE

      # Step 2: Exclude custom_fields
      exclude_custom_fields!(payload)

      return payload if payload_size(payload) <= MAX_PAYLOAD_SIZE

      # Step 3: Raise error if still over limit
      raise PayloadTooLargeError, "Payload exceeds maximum size of #{MAX_PAYLOAD_SIZE} bytes"
    end

    def payload_size(payload)
      payload.to_json.bytesize
    end

    def exclude_custom_fields!(payload)
      [:issue, :time_entry].each do |key|
        if payload[key].is_a?(Hash) && payload[key][:custom_fields].is_a?(Array)
          payload[key][:custom_fields] = []
          payload[:custom_fields_excluded] = true
        end
      end
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 55 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add payload size enforcement with graceful truncation"
```

---

## Task 15: Journal Integration for Issue Changes

**Files:**
- Modify: `app/services/webhook/payload_builder.rb`
- Modify: `test/unit/webhook/payload_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/payload_builder_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "build includes journal info for issue updates when present" do
    issue = Issue.find(1)
    journal = issue.journals.first || Journal.create!(
      journalized: issue,
      user: User.find(2),
      notes: "Test note"
    )

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "updated",
      occurred_at: Time.current,
      resource: issue,
      actor: journal.user,
      project: issue.project,
      journal: journal,
      saved_changes: { "status_id" => [1, 2] }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:journal]
    assert_equal journal.id, result[:journal][:id]
    assert_equal journal.notes, result[:journal][:notes]
  end

  test "build does not include journal when not present" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:journal]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```


Expected: FAIL - journal key missing

**Step 3: Add journal serialization**

```ruby
# app/services/webhook/payload_builder.rb - add journal support
module RedmineWebhookPlugin::Webhook
  class PayloadBuilder
    # ... existing code ...

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload.merge!(build_resource_data)
      payload[:changes] = build_changes_for_event if update_action?
      payload[:journal] = serialize_journal(event_data[:journal]) if event_data[:journal]
      enforce_size_limit(payload)
    end

    private

    def serialize_journal(journal)
      return nil if journal.nil?

      {
        id: journal.id,
        notes: journal.notes,
        created_on: format_timestamp(journal.created_on)
      }
    end

    # ... rest of existing methods ...
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 57 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/payload_builder.rb test/unit/webhook/payload_builder_test.rb
git commit -m "feat(ws-c): add journal serialization for issue update context"
```

## Task 15: Journal Integration ✅ COMPLETE

### Status
- [x] Implementation done
- [x] Tests passing on all supported Redmine versions (5.1.0, 5.1.10, 6.1.0)

### Summary
Added journal serialization for issue update context:
- Issue patch now captures `@current_journal` during webhook_capture_changes
- PayloadBuilder serializes journal with id, notes, created_on timestamp
- Journal data is included in webhook payloads for "updated" issue events

### Implementation Details
- Modified `lib/redmine_webhook_plugin/patches/issue_patch.rb`:
  - Added `@webhook_journal = @current_journal` capture in `webhook_capture_changes`
  - Updated `webhook_event_data` to include journal for "updated" actions only

- Modified `app/services/webhook/payload_builder.rb`:
  - Added `serialize_journal` method (returns id, notes, created_on)
  - Updated `build` method to include journal when present

- Added `test/unit/issue_patch_test.rb`:
  - Added 2 test cases for journal integration

- All code now uses `RedmineWebhookPlugin::Webhook::` namespace properly

---

## Task 16: Run All Workstream C Tests

**Step 1: Run full test suite**

Run:
```bash
# Primary version
VERSION=5.1.0 tools/test/run-test.sh

# Also verify on other versions
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
```


Expected: All tests pass

**Step 2: Verify PayloadBuilder integration in Rails console**

Run: `cd /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.1 && bundle exec rails console -e test`

```ruby
# Test minimal issue payload
issue = Issue.first
event_data = {
  event_id: SecureRandom.uuid,
  event_type: "issue",
  action: "created",
  occurred_at: Time.current,
  resource: issue,
  actor: issue.author,
  project: issue.project
}
builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
payload = builder.build
puts JSON.pretty_generate(payload)

# Test full issue payload with changes
event_data[:action] = "updated"
event_data[:saved_changes] = { "status_id" => [1, 2] }
builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
payload = builder.build
puts JSON.pretty_generate(payload)

# Test time entry payload
time_entry = TimeEntry.first
event_data = {
  event_id: SecureRandom.uuid,
  event_type: "time_entry",
  action: "created",
  occurred_at: Time.current,
  resource: time_entry,
  actor: time_entry.user,
  project: time_entry.project
}
builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
payload = builder.build
puts JSON.pretty_generate(payload)

exit
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat(ws-c): complete PayloadBuilder service implementation"
```

---

## Acceptance Criteria Checklist

- [ ] PayloadBuilder service exists at `app/services/webhook/payload_builder.rb`
- [ ] Minimal payload includes only IDs and URLs
- [ ] Full payload includes complete resource snapshot
- [ ] Changes array has `old`/`new` with `raw` and `text` values
- [ ] Custom field changes are tracked separately with `kind: "custom_field"`
- [ ] Delete events include pre-delete snapshot with `snapshot_type: "pre_delete"`
- [ ] Oversized payloads (>1MB) are truncated gracefully:
  - Changes limited to 100 entries
  - Custom fields excluded if still over
  - Error raised only if core data exceeds limit
- [ ] All URL helpers use `Setting.protocol` and `Setting.host_name`
- [ ] Journal info included for issue update events
- [ ] All unit tests pass