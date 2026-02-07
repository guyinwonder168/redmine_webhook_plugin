# P0: Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the database schema and base models (RedmineWebhookPlugin::Webhook::Endpoint, RedmineWebhookPlugin::Webhook::Delivery) that all other workstreams depend on.

**Architecture:** Two ActiveRecord models under `Webhook` module namespace. Endpoints define where/how to send webhooks; Deliveries track each send attempt with status, payload snapshot, and retry info. Uses Redmine's migration system and follows plugin conventions.

**Tech Stack:** Ruby/Rails, ActiveRecord, Redmine Plugin API, Minitest

**Must complete before:** Workstreams A, B, C, D

## Redmine 7.0+ Compatibility

- Detect native webhooks via `defined?(::Webhook) && ::Webhook < ApplicationRecord`.
- When native exists, disable or bypass native delivery; the plugin remains authoritative.
- Use `RedmineWebhookPlugin::` for plugin service namespaces to avoid conflicts with native `Webhook`.

---

## Testing Environment (Podman)

All tests run inside Podman containers to ensure consistent Ruby/Rails versions. The workspace has three Redmine versions available:

| Version | Directory | Image | Ruby | Rail |
|---------|-----------|-------|------|------|
| 5.1.0 | `.redmine-test/redmine-5.1.0/` | `redmine-dev:5.1.0` | 3.2.2 |6.1.7.6|
| 5.1.10 | `.redmine-test/redmine-5.1.10/` | `redmine-dev:5.1.10` | 3.2.2 |6.1.7.10|
| 6.1.0 | `.redmine-test/redmine-6.1.0/` | `redmine-dev:6.1.0` | 3.2.4 |7.2.2.2|
| 7.0.0 | `.redmine-test/redmine-7.0.0-dev/` | `redmine-7.0.0-dev` | 3.3.4 |8.0.4|

**Primary development target:** Redmine 5.1.0 (use `VERSION=5.1.0 tools/test/run-test.sh` for full suite).

> **IMPORTANT:** Every task MUST be verified on ALL THREE Redmine versions before marking complete.

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
```

### Running Individual Test Files

For TDD cycles, run individual test files with this pattern:

```bash
# From /media/eddy/hdd/Project/redmine_webhook_plugin
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'
```

### Running Full Plugin Test Suite

```bash
VERSION=5.1.0 tools/test/run-test.sh
```

### Running Migrations Only

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin RAILS_ENV=test'
```

### Running Rails Console

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec rails console -e test'
```

---

## Task 1: Create Webhook Module ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 2 runs, 3 assertions |
| 5.1.10 | ✅ PASS | 2 runs, 3 assertions |
| 6.1.0 | ✅ PASS | 2 runs, 3 assertions |

**Files:**
- Create: `app/models/webhook.rb`
- Test: `test/unit/webhook_module_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook_module_test.rb
require File.expand_path("../test_helper", __dir__)

class WebhookModuleTest < ActiveSupport::TestCase
  test "Webhook module is defined" do
    assert defined?(Webhook), "Webhook module should be defined"
    assert_kind_of Module, Webhook
  end

  test "Webhook module has table_name_prefix" do
    assert_equal "webhook_", Webhook.table_name_prefix
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_module_test.rb -v'
```

Expected: FAIL with "uninitialized constant Webhook" or similar

**Step 3: Write minimal implementation**

```ruby
# app/models/webhook.rb
module RedmineWebhookPlugin::Webhook
  def self.table_name_prefix
    "webhook_"
  end
end
```

**Step 4: Update init.rb to require the module**

```ruby
# init.rb - add after existing require
require_relative "lib/redmine_webhook_plugin"

Rails.application.config.to_prepare do
  require_dependency File.expand_path("../app/models/webhook", __FILE__)
end

Redmine::Plugin.register :redmine_webhook_plugin do
  # ... existing code
end
```

**Step 5: Run test to verify it passes (5.1.0)**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_module_test.rb -v'
```

Expected: PASS - 2 tests, 0 failures

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_module_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_module_test.rb -v'
```

Expected: PASS on all versions

**Step 7: Commit**

```bash
git add app/models/webhook.rb test/unit/webhook_module_test.rb init.rb
git commit -m "feat(p0): add Webhook module with table_name_prefix"
```

---

## Task 2: Create Endpoints Migration ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 1 run, 29 assertions |
| 5.1.10 | ✅ PASS | 1 run, 29 assertions |
| 6.1.0 | ✅ PASS | 1 run, 29 assertions |

**Files:**
- Create: `db/migrate/001_create_webhook_endpoints.rb`
- Test: `test/unit/webhook_endpoint_migration_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook_endpoint_migration_test.rb
require File.expand_path("../test_helper", __dir__)

class WebhookEndpointMigrationTest < ActiveSupport::TestCase
  test "webhook_endpoints table exists with required columns" do
    assert ActiveRecord::Base.connection.table_exists?(:webhook_endpoints),
           "webhook_endpoints table should exist"

    columns = ActiveRecord::Base.connection.columns(:webhook_endpoints).map(&:name)

    # Core columns
    assert_includes columns, "id"
    assert_includes columns, "name"
    assert_includes columns, "url"
    assert_includes columns, "enabled"
    assert_includes columns, "webhook_user_id"

    # Config columns
    assert_includes columns, "payload_mode"
    assert_includes columns, "events_config"
    assert_includes columns, "project_ids"
    assert_includes columns, "retry_config"

    # Request options
    assert_includes columns, "timeout"
    assert_includes columns, "ssl_verify"
    assert_includes columns, "bulk_replay_rate_limit"

    # Timestamps
    assert_includes columns, "created_at"
    assert_includes columns, "updated_at"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_endpoint_migration_test.rb -v'
```

Expected: FAIL with "webhook_endpoints table should exist"

**Step 3: Write the migration**

```ruby
# db/migrate/001_create_webhook_endpoints.rb
class CreateWebhookEndpoints < ActiveRecord::Migration[6.1]
  def change
    create_table :webhook_endpoints do |t|
      # Core
      t.string :name, null: false
      t.text :url, null: false
      t.boolean :enabled, default: true, null: false
      t.integer :webhook_user_id

      # Config (JSON stored as text for SQLite compatibility)
      t.string :payload_mode, default: "minimal", null: false
      t.text :events_config
      t.text :project_ids
      t.text :retry_config

      # Request options
      t.integer :timeout, default: 30
      t.boolean :ssl_verify, default: true
      t.integer :bulk_replay_rate_limit, default: 10

      t.timestamps null: false
    end

    add_index :webhook_endpoints, :webhook_user_id
    add_index :webhook_endpoints, :enabled
  end
end
```

**Step 4: Run migration**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin RAILS_ENV=test'
```

Expected: Migration runs successfully

**Step 5: Run test to verify it passes (5.1.0)**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_endpoint_migration_test.rb -v'
```

Expected: PASS - 1 test, 0 failures

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_endpoint_migration_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_endpoint_migration_test.rb -v'
```

Expected: PASS on all versions

**Step 7: Commit**

```bash
git add db/migrate/001_create_webhook_endpoints.rb test/unit/webhook_endpoint_migration_test.rb
git commit -m "feat(p0): add webhook_endpoints migration"
```

---

## Task 3: Create Deliveries Migration ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 2 runs, 50 assertions |
| 5.1.10 | ✅ PASS | 2 runs, 50 assertions |
| 6.1.0 | ✅ PASS | 2 runs, 50 assertions |

**Files:**
- Create: `db/migrate/002_create_webhook_deliveries.rb`
- Test: `test/unit/webhook_delivery_migration_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook_delivery_migration_test.rb
require File.expand_path("../test_helper", __dir__)

class WebhookDeliveryMigrationTest < ActiveSupport::TestCase
  test "webhook_deliveries table exists with required columns" do
    assert ActiveRecord::Base.connection.table_exists?(:webhook_deliveries),
           "webhook_deliveries table should exist"

    columns = ActiveRecord::Base.connection.columns(:webhook_deliveries).map(&:name)

    # References
    assert_includes columns, "endpoint_id"
    assert_includes columns, "webhook_user_id"

    # Event identification
    assert_includes columns, "event_id"
    assert_includes columns, "event_type"
    assert_includes columns, "action"
    assert_includes columns, "resource_type"
    assert_includes columns, "resource_id"
    assert_includes columns, "sequence_number"

    # Payload
    assert_includes columns, "payload"
    assert_includes columns, "endpoint_url"
    assert_includes columns, "retry_policy_snapshot"

    # Status tracking
    assert_includes columns, "status"
    assert_includes columns, "attempt_count"
    assert_includes columns, "http_status"
    assert_includes columns, "error_code"

    # Timing
    assert_includes columns, "scheduled_at"
    assert_includes columns, "delivered_at"
    assert_includes columns, "duration_ms"

    # Locking
    assert_includes columns, "locked_at"
    assert_includes columns, "locked_by"

    # Metadata
    assert_includes columns, "response_body_excerpt"
    assert_includes columns, "api_key_fingerprint"
    assert_includes columns, "is_test"
  end

  test "webhook_deliveries has required indexes" do
    indexes = ActiveRecord::Base.connection.indexes(:webhook_deliveries).map(&:columns)

    assert indexes.any? { |cols| cols.include?("endpoint_id") },
           "Should have index on endpoint_id"
    assert indexes.any? { |cols| cols.include?("event_id") },
           "Should have index on event_id"
    assert indexes.any? { |cols| cols.include?("scheduled_at") },
           "Should have index on scheduled_at"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_delivery_migration_test.rb -v'
```

Expected: FAIL with "webhook_deliveries table should exist"

**Step 3: Write the migration**

```ruby
# db/migrate/002_create_webhook_deliveries.rb
class CreateWebhookDeliveries < ActiveRecord::Migration[6.1]
  def change
    create_table :webhook_deliveries do |t|
      # References
      t.integer :endpoint_id
      t.integer :webhook_user_id

      # Event identification
      t.string :event_id, limit: 36, null: false
      t.string :event_type, null: false
      t.string :action, null: false
      t.string :resource_type
      t.integer :resource_id
      t.bigint :sequence_number

      # Payload (use text for large JSON, mediumtext for MySQL)
      t.text :payload, limit: 16.megabytes - 1
      t.text :endpoint_url
      t.text :retry_policy_snapshot

      # Status tracking
      t.string :status, default: "pending", null: false
      t.integer :attempt_count, default: 0, null: false
      t.integer :http_status
      t.string :error_code

      # Timing
      t.datetime :scheduled_at
      t.datetime :delivered_at
      t.integer :duration_ms

      # Locking (for DB runner)
      t.datetime :locked_at
      t.string :locked_by

      # Metadata
      t.text :response_body_excerpt
      t.string :api_key_fingerprint
      t.boolean :is_test, default: false

      t.timestamps null: false
    end

    add_index :webhook_deliveries, [:endpoint_id, :status]
    add_index :webhook_deliveries, [:resource_type, :resource_id]
    add_index :webhook_deliveries, :event_id
    add_index :webhook_deliveries, :scheduled_at
    add_index :webhook_deliveries, :status
  end
end
```

**Step 4: Run migration**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin RAILS_ENV=test'
```

Expected: Migration runs successfully

**Step 5: Run test to verify it passes (5.1.0)**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_delivery_migration_test.rb -v'
```

Expected: PASS - 2 tests, 0 failures

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_delivery_migration_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_delivery_migration_test.rb -v'
```

Expected: PASS on all versions

**Step 7: Commit**

```bash
git add db/migrate/002_create_webhook_deliveries.rb test/unit/webhook_delivery_migration_test.rb
git commit -m "feat(p0): add webhook_deliveries migration"
```

---

## Task 4: Create Endpoint Model - Basic Structure ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 3 runs, 4 assertions |
| 5.1.10 | ✅ PASS | 3 runs, 4 assertions |
| 6.1.0 | ✅ PASS | 3 runs, 4 assertions |

**Files:**
- Create: `app/models/webhook/endpoint.rb`
- Test: `test/unit/webhook/endpoint_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/endpoint_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::EndpointTest < ActiveSupport::TestCase
  test "Endpoint class exists under Webhook namespace" do
    assert defined?(RedmineWebhookPlugin::Webhook::Endpoint), "RedmineWebhookPlugin::Webhook::Endpoint should be defined"
    assert_equal "webhook_endpoints", RedmineWebhookPlugin::Webhook::Endpoint.table_name
  end

  test "Endpoint belongs to webhook_user" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
    assert endpoint.respond_to?(:webhook_user),
           "Endpoint should have webhook_user association"
  end

  test "Endpoint has many deliveries" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
    assert endpoint.respond_to?(:deliveries),
           "Endpoint should have deliveries association"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::Endpoint"

**Step 3: Write minimal implementation**

```ruby
# app/models/webhook/endpoint.rb
class RedmineWebhookPlugin::Webhook::Endpoint < ActiveRecord::Base
  belongs_to :webhook_user, class_name: "User", optional: true
  has_many :deliveries, class_name: "RedmineWebhookPlugin::Webhook::Delivery", foreign_key: :endpoint_id, dependent: :nullify
end
```

**Step 4: Update init.rb to require the model**

```ruby
# init.rb - update the to_prepare block
Rails.application.config.to_prepare do
  require_dependency File.expand_path("../app/models/webhook", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/endpoint", __FILE__)
end
```

**Step 5: Run test to verify it passes (5.1.0)**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS - 3 tests, 0 failures

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS on all versions

**Step 7: Commit**

```bash
git add app/models/webhook/endpoint.rb test/unit/webhook/endpoint_test.rb init.rb
git commit -m "feat(p0): add RedmineWebhookPlugin::Webhook::Endpoint model with associations"
```

---

## Task 5: Endpoint Model - Validations ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 9 runs, 17 assertions |
| 5.1.10 | ✅ PASS | 9 runs, 17 assertions |
| 6.1.0 | ✅ PASS | 9 runs, 17 assertions |

**Files:**
- Modify: `app/models/webhook/endpoint.rb`
- Modify: `test/unit/webhook/endpoint_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/endpoint_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::EndpointTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "validates name presence" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: nil, url: "https://example.com")
    assert_not endpoint.valid?
    assert_includes endpoint.errors[:name], "can't be blank"
  end

  test "validates name uniqueness" do
    RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")
    duplicate = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://other.com")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "validates url presence" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: nil)
    assert_not endpoint.valid?
    assert_includes endpoint.errors[:url], "can't be blank"
  end

  test "validates url format - must be http or https" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "ftp://example.com")
    assert_not endpoint.valid?
    assert_includes endpoint.errors[:url], "must be a valid HTTP or HTTPS URL"
  end

  test "accepts valid https url" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com/webhook")
    endpoint.valid?
    assert_empty endpoint.errors[:url]
  end

  test "accepts valid http url" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "http://localhost:3000/webhook")
    endpoint.valid?
    assert_empty endpoint.errors[:url]
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: FAIL - validations not implemented yet

**Step 3: Add validations to model**

```ruby
# app/models/webhook/endpoint.rb
class RedmineWebhookPlugin::Webhook::Endpoint < ActiveRecord::Base
  belongs_to :webhook_user, class_name: "User", optional: true
  has_many :deliveries, class_name: "RedmineWebhookPlugin::Webhook::Delivery", foreign_key: :endpoint_id, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validate :url_must_be_http_or_https

  private

  def url_must_be_http_or_https
    return if url.blank?

    begin
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        errors.add(:url, "must be a valid HTTP or HTTPS URL")
      end
    rescue URI::InvalidURIError
      errors.add(:url, "must be a valid HTTP or HTTPS URL")
    end
  end
end
```

**Step 4: Run test to verify it passes (5.1.0)**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS - 9 tests, 0 failures

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS on all versions

**Step 6: Commit**

```bash
git add app/models/webhook/endpoint.rb test/unit/webhook/endpoint_test.rb
git commit -m "feat(p0): add Endpoint validations for name and url"
```

---

## Task 6: Endpoint Model - JSON Accessors ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 14 runs, 24 assertions |
| 5.1.10 | ✅ PASS | 14 runs, 24 assertions |
| 6.1.0 | ✅ PASS | 14 runs, 24 assertions |

**Files:**
- Modify: `app/models/webhook/endpoint.rb`
- Modify: `test/unit/webhook/endpoint_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/endpoint_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::EndpointTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "events_config stores and retrieves hash" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.events_config = { "issue" => { "created" => true, "updated" => false } }
    endpoint.save!
    endpoint.reload

    assert_equal({ "issue" => { "created" => true, "updated" => false } }, endpoint.events_config)
  end

  test "events_config defaults to empty hash" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
    assert_equal({}, endpoint.events_config)
  end

  test "project_ids stores and retrieves array" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.project_ids_array = [1, 2, 3]
    endpoint.save!
    endpoint.reload

    assert_equal [1, 2, 3], endpoint.project_ids_array
  end

  test "project_ids_array defaults to empty array" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
    assert_equal [], endpoint.project_ids_array
  end

  test "retry_config stores and retrieves hash with defaults" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.save!
    endpoint.reload

    config = endpoint.retry_config
    assert_equal 5, config["max_attempts"]
    assert_equal 60, config["base_delay"]
    assert_equal 3600, config["max_delay"]
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: FAIL - JSON accessor methods not defined

**Step 3: Add JSON accessors to model**

```ruby
# app/models/webhook/endpoint.rb
class RedmineWebhookPlugin::Webhook::Endpoint < ActiveRecord::Base
  DEFAULT_RETRY_CONFIG = {
    "max_attempts" => 5,
    "base_delay" => 60,
    "max_delay" => 3600,
    "retryable_statuses" => [408, 429, 500, 502, 503, 504]
  }.freeze

  belongs_to :webhook_user, class_name: "User", optional: true
  has_many :deliveries, class_name: "RedmineWebhookPlugin::Webhook::Delivery", foreign_key: :endpoint_id, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validate :url_must_be_http_or_https

  def events_config
    val = read_attribute(:events_config)
    val.present? ? JSON.parse(val) : {}
  rescue JSON::ParserError
    {}
  end

  def events_config=(hash)
    write_attribute(:events_config, hash.to_json)
  end

  def project_ids_array
    val = read_attribute(:project_ids)
    val.present? ? JSON.parse(val) : []
  rescue JSON::ParserError
    []
  end

  def project_ids_array=(arr)
    write_attribute(:project_ids, arr.to_json)
  end

  def retry_config
    val = read_attribute(:retry_config)
    base = DEFAULT_RETRY_CONFIG.dup
    if val.present?
      begin
        base.merge!(JSON.parse(val))
      rescue JSON::ParserError
        # ignore parse errors, use defaults
      end
    end
    base
  end

  def retry_config=(hash)
    write_attribute(:retry_config, hash.to_json)
  end

  private

  def url_must_be_http_or_https
    return if url.blank?

    begin
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        errors.add(:url, "must be a valid HTTP or HTTPS URL")
      end
    rescue URI::InvalidURIError
      errors.add(:url, "must be a valid HTTP or HTTPS URL")
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS - 14 tests, 0 failures

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS on all versions

**Step 6: Commit**

```bash
git add app/models/webhook/endpoint.rb test/unit/webhook/endpoint_test.rb
git commit -m "feat(p0): add JSON accessors for events_config, project_ids, retry_config"
```

---

## Task 7: Endpoint Model - Scopes and Event Matching ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 19 runs, 37 assertions |
| 5.1.10 | ✅ PASS | 19 runs, 37 assertions |
| 6.1.0 | ✅ PASS | 19 runs, 37 assertions |

**Files:**
- Modify: `app/models/webhook/endpoint.rb`
- Modify: `test/unit/webhook/endpoint_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/endpoint_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::EndpointTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "enabled scope returns only enabled endpoints" do
    enabled = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Enabled", url: "https://a.com", enabled: true)
    disabled = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Disabled", url: "https://b.com", enabled: false)

    result = RedmineWebhookPlugin::Webhook::Endpoint.enabled
    assert_includes result, enabled
    assert_not_includes result, disabled
  end

  test "matches_event? returns true when event enabled and no project filter" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.events_config = { "issue" => { "created" => true } }

    assert endpoint.matches_event?("issue", "created", 1)
    assert endpoint.matches_event?("issue", "created", 999)
  end

  test "matches_event? returns false when event not enabled" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.events_config = { "issue" => { "created" => true, "updated" => false } }

    assert_not endpoint.matches_event?("issue", "updated", 1)
    assert_not endpoint.matches_event?("issue", "deleted", 1)
    assert_not endpoint.matches_event?("time_entry", "created", 1)
  end

  test "matches_event? respects project allowlist" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.events_config = { "issue" => { "created" => true } }
    endpoint.project_ids_array = [1, 2]

    assert endpoint.matches_event?("issue", "created", 1)
    assert endpoint.matches_event?("issue", "created", 2)
    assert_not endpoint.matches_event?("issue", "created", 3)
  end

  test "matches_event? allows all projects when project_ids empty" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com")
    endpoint.events_config = { "issue" => { "created" => true } }
    endpoint.project_ids_array = []

    assert endpoint.matches_event?("issue", "created", 999)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: FAIL - scope and matches_event? not defined

**Step 3: Add scope and method**

```ruby
# app/models/webhook/endpoint.rb - add after validations
class RedmineWebhookPlugin::Webhook::Endpoint < ActiveRecord::Base
  # ... existing code ...

  scope :enabled, -> { where(enabled: true) }

  def matches_event?(event_type, action, project_id)
    return false unless event_enabled?(event_type, action)
    return true if project_ids_array.empty?

    project_ids_array.include?(project_id.to_i)
  end

  private

  def event_enabled?(event_type, action)
    config = events_config[event_type.to_s]
    return false unless config.is_a?(Hash)

    config[action.to_s] == true
  end

  # ... existing private methods ...
end
```

**Step 4: Run test to verify it passes**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS - 19 tests, 0 failures

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS on all versions

**Step 6: Commit**

```bash
git add app/models/webhook/endpoint.rb test/unit/webhook/endpoint_test.rb
git commit -m "feat(p0): add enabled scope and matches_event? method"
```

---

## Task 8: Create Delivery Model - Basic Structure ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 3 runs, 9 assertions |
| 5.1.10 | ✅ PASS | 3 runs, 9 assertions |
| 6.1.0 | ✅ PASS | 3 runs, 9 assertions |

**Files:**
- Create: `app/models/webhook/delivery.rb`
- Test: `test/unit/webhook/delivery_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/delivery_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DeliveryTest < ActiveSupport::TestCase
  test "Delivery class exists under Webhook namespace" do
    assert defined?(RedmineWebhookPlugin::Webhook::Delivery), "RedmineWebhookPlugin::Webhook::Delivery should be defined"
    assert_equal "webhook_deliveries", RedmineWebhookPlugin::Webhook::Delivery.table_name
  end

  test "Delivery belongs to endpoint" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.new
    assert delivery.respond_to?(:endpoint),
           "Delivery should have endpoint association"
  end

  test "Delivery has status constants" do
    assert_equal "pending", RedmineWebhookPlugin::Webhook::Delivery::PENDING
    assert_equal "delivering", RedmineWebhookPlugin::Webhook::Delivery::DELIVERING
    assert_equal "success", RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    assert_equal "failed", RedmineWebhookPlugin::Webhook::Delivery::FAILED
    assert_equal "dead", RedmineWebhookPlugin::Webhook::Delivery::DEAD
    assert_equal "endpoint_deleted", RedmineWebhookPlugin::Webhook::Delivery::ENDPOINT_DELETED
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::Delivery"

**Step 3: Write minimal implementation**

```ruby
# app/models/webhook/delivery.rb
class RedmineWebhookPlugin::Webhook::Delivery < ActiveRecord::Base
  PENDING = "pending".freeze
  DELIVERING = "delivering".freeze
  SUCCESS = "success".freeze
  FAILED = "failed".freeze
  DEAD = "dead".freeze
  ENDPOINT_DELETED = "endpoint_deleted".freeze

  STATUSES = [PENDING, DELIVERING, SUCCESS, FAILED, DEAD, ENDPOINT_DELETED].freeze

  belongs_to :endpoint, class_name: "RedmineWebhookPlugin::Webhook::Endpoint", optional: true
  belongs_to :webhook_user, class_name: "User", optional: true
end
```

**Step 4: Update init.rb to require the model**

```ruby
# init.rb - update the to_prepare block
Rails.application.config.to_prepare do
  require_dependency File.expand_path("../app/models/webhook", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/endpoint", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/delivery", __FILE__)
end
```

**Step 5: Run test to verify it passes (5.1.0)**

```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: PASS - 3 tests, 0 failures

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: PASS on all versions

**Step 7: Commit**

```bash
git add app/models/webhook/delivery.rb test/unit/webhook/delivery_test.rb init.rb
git commit -m "feat(p0): add RedmineWebhookPlugin::Webhook::Delivery model with status constants"
```

---

## Task 9: Delivery Model - Validations and Scopes ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 8 runs, 28 assertions |
| 5.1.10 | ✅ PASS | 8 runs, 28 assertions |
| 6.1.0 | ✅ PASS | 8 runs, 28 assertions |

**Files:**
- Modify: `app/models/webhook/delivery.rb`
- Modify: `test/unit/webhook/delivery_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/delivery_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::DeliveryTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "validates event_id presence" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.new(event_id: nil, event_type: "issue", action: "created")
    assert_not delivery.valid?
    assert_includes delivery.errors[:event_id], "can't be blank"
  end

  test "validates status inclusion" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.new(
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: "invalid_status"
    )
    assert_not delivery.valid?
    assert_includes delivery.errors[:status], "is not included in the list"
  end

  test "pending scope returns only pending deliveries" do
    pending = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: "pending"
    )
    success = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: "success"
    )

    result = RedmineWebhookPlugin::Webhook::Delivery.pending
    assert_includes result, pending
    assert_not_includes result, success
  end

  test "failed scope returns only failed deliveries" do
    failed = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: "failed"
    )
    pending = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: "pending"
    )

    result = RedmineWebhookPlugin::Webhook::Delivery.failed
    assert_includes result, failed
    assert_not_includes result, pending
  end

  test "due scope returns deliveries with scheduled_at <= now" do
    past = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created",
      status: "pending", scheduled_at: 1.hour.ago
    )
    future = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created",
      status: "pending", scheduled_at: 1.hour.from_now
    )
    no_schedule = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created",
      status: "pending", scheduled_at: nil
    )

    result = RedmineWebhookPlugin::Webhook::Delivery.due
    assert_includes result, past
    assert_includes result, no_schedule
    assert_not_includes result, future
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: FAIL - validations and scopes not defined

**Step 3: Add validations and scopes**

```ruby
# app/models/webhook/delivery.rb
class RedmineWebhookPlugin::Webhook::Delivery < ActiveRecord::Base
  PENDING = "pending".freeze
  DELIVERING = "delivering".freeze
  SUCCESS = "success".freeze
  FAILED = "failed".freeze
  DEAD = "dead".freeze
  ENDPOINT_DELETED = "endpoint_deleted".freeze

  STATUSES = [PENDING, DELIVERING, SUCCESS, FAILED, DEAD, ENDPOINT_DELETED].freeze

  belongs_to :endpoint, class_name: "RedmineWebhookPlugin::Webhook::Endpoint", optional: true
  belongs_to :webhook_user, class_name: "User", optional: true

  validates :event_id, presence: true
  validates :event_type, presence: true
  validates :action, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: PENDING) }
  scope :failed, -> { where(status: FAILED) }
  scope :due, -> { where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current) }
end
```

**Step 4: Run test to verify it passes**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: PASS - 8 tests, 0 failures

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: PASS on all versions

**Step 6: Commit**

```bash
git add app/models/webhook/delivery.rb test/unit/webhook/delivery_test.rb
git commit -m "feat(p0): add Delivery validations and scopes"
```

---

## Task 10: Delivery Model - Status Transition Methods ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26)
| Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 14 runs, 56 assertions |
| 5.1.10 | ✅ PASS | 14 runs, 56 assertions |
| 6.1.0 | ✅ PASS | 14 runs, 56 assertions |

**Files:**
- Modify: `app/models/webhook/delivery.rb`
- Modify: `test/unit/webhook/delivery_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/delivery_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::DeliveryTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "can_retry? returns true for pending and failed" do
    pending = RedmineWebhookPlugin::Webhook::Delivery.new(status: "pending")
    failed = RedmineWebhookPlugin::Webhook::Delivery.new(status: "failed")
    success = RedmineWebhookPlugin::Webhook::Delivery.new(status: "success")
    dead = RedmineWebhookPlugin::Webhook::Delivery.new(status: "dead")

    assert pending.can_retry?
    assert failed.can_retry?
    assert_not success.can_retry?
    assert_not dead.can_retry?
  end

  test "mark_delivering! updates status and lock" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: "pending"
    )

    delivery.mark_delivering!("runner-123")

    assert_equal "delivering", delivery.status
    assert_equal "runner-123", delivery.locked_by
    assert_not_nil delivery.locked_at
  end

  test "mark_success! updates status and clears lock" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created",
      status: "delivering", locked_by: "runner-123", locked_at: Time.current
    )

    delivery.mark_success!(200, "OK", 150)

    assert_equal "success", delivery.status
    assert_equal 200, delivery.http_status
    assert_equal "OK", delivery.response_body_excerpt
    assert_equal 150, delivery.duration_ms
    assert_not_nil delivery.delivered_at
    assert_nil delivery.locked_by
    assert_nil delivery.locked_at
  end

  test "mark_failed! updates status and increments attempt_count" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created",
      status: "delivering", attempt_count: 1
    )

    delivery.mark_failed!("connection_timeout", nil, "Connection timed out")

    assert_equal "failed", delivery.status
    assert_equal "connection_timeout", delivery.error_code
    assert_equal "Connection timed out", delivery.response_body_excerpt
    assert_equal 2, delivery.attempt_count
    assert_nil delivery.locked_by
    assert_nil delivery.locked_at
  end

  test "mark_dead! updates status to dead" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: "failed"
    )

    delivery.mark_dead!

    assert_equal "dead", delivery.status
  end

  test "reset_for_replay! resets status to pending" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid, event_type: "issue", action: "created",
      status: "dead", attempt_count: 5, error_code: "connection_refused"
    )

    delivery.reset_for_replay!

    assert_equal "pending", delivery.status
    assert_equal 0, delivery.attempt_count
    assert_nil delivery.error_code
    assert_nil delivery.http_status
    assert_nil delivery.scheduled_at
  end
end
```

**Step 2: Run test to verify it fails**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: FAIL - status transition methods not defined

**Step 3: Add status transition methods**

```ruby
# app/models/webhook/delivery.rb
class RedmineWebhookPlugin::Webhook::Delivery < ActiveRecord::Base
  # ... existing constants, associations, validations, scopes ...

  def can_retry?
    [PENDING, FAILED].include?(status)
  end

  def mark_delivering!(runner_id)
    update!(
      status: DELIVERING,
      locked_by: runner_id,
      locked_at: Time.current
    )
  end

  def mark_success!(http_status, response_excerpt, duration_ms)
    update!(
      status: SUCCESS,
      http_status: http_status,
      response_body_excerpt: response_excerpt,
      duration_ms: duration_ms,
      delivered_at: Time.current,
      locked_by: nil,
      locked_at: nil
    )
  end

  def mark_failed!(error_code, http_status, response_excerpt)
    update!(
      status: FAILED,
      error_code: error_code,
      http_status: http_status,
      response_body_excerpt: response_excerpt,
      attempt_count: attempt_count + 1,
      locked_by: nil,
      locked_at: nil
    )
  end

  def mark_dead!
    update!(status: DEAD)
  end

  def reset_for_replay!
    update!(
      status: PENDING,
      attempt_count: 0,
      error_code: nil,
      http_status: nil,
      scheduled_at: nil,
      locked_by: nil,
      locked_at: nil
    )
  end
end
```

**Step 4: Run test to verify it passes**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: PASS - 14 tests, 0 failures

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_test.rb -v'
```

Expected: PASS on all versions

**Step 6: Commit**

```bash
git add app/models/webhook/delivery.rb test/unit/webhook/delivery_test.rb
git commit -m "feat(p0): add Delivery status transition methods"
```

---

## Task 11: Run All P0 Tests ✅ VERIFIED

**Status:** Verified on all 3 Redmine versions (2025-12-26, updated 2025-12-29)
 | Version | Result | Stats |
|---------|--------|-------|
| 5.1.0 | ✅ PASS | 39 runs, 176 assertions |
| 5.1.10 | ✅ PASS | 39 runs, 176 assertions |
| 6.1.0 | ✅ PASS | 53 runs, 227 assertions |

**Step 1: Run full test suite for P0 (all three Redmine versions)**

```bash
# Primary version
VERSION=5.1.0 tools/test/run-test.sh

# Also verify on other versions
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
```

Expected: All tests pass on all three versions (sanity + module + migrations + endpoint + delivery)

**Step 2: Verify in Rails console**

```bash
podman run --rm \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec rails console -e test'
```

```ruby
# Test basic CRUD
endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")
endpoint.events_config = { "issue" => { "created" => true } }
endpoint.save!
endpoint.matches_event?("issue", "created", 1) # => true

delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
  endpoint: endpoint,
  event_id: SecureRandom.uuid,
  event_type: "issue",
  action: "created"
)
delivery.can_retry? # => true
delivery.mark_delivering!("test-runner")
delivery.status # => "delivering"

exit
```

**Step 3: Commit final P0**

```bash
git add -A
git commit -m "feat(p0): complete foundation - Webhook module, Endpoint and Delivery models"
```

---

## Acceptance Criteria Checklist

- [ ] Migrations run successfully on fresh Redmine 5.1.0+
- [ ] `RedmineWebhookPlugin::Webhook::Endpoint.new` instantiates without error
- [ ] `RedmineWebhookPlugin::Webhook::Delivery.new` instantiates without error
- [ ] Endpoint validates name uniqueness and URL format
- [ ] Endpoint JSON accessors work (events_config, project_ids, retry_config)
- [ ] Endpoint.matches_event? filters correctly by event type, action, and project
- [ ] Delivery status transitions work correctly
- [ ] All unit tests pass on Redmine 5.1.0, 5.1.10, and 6.1.0
