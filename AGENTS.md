# AGENTS.md - Redmine Webhook Plugin

This file provides guidance for agentic coding agents operating in this repository.

## Quick Reference

- **Project**: Redmine Webhook Plugin (outbound webhooks for issues and time entries)
- **Language**: Ruby 3.x with Rails 6.x/7.x
- **Min Redmine Version**: 5.1.0
- **Tested Against**: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
- **Test Framework**: Minitest
- **ChangeLog**: update the `CHANGELOG.md` before every commit (local/remote)

## Known Issues & Workarounds

### Redmine 6.1.0+ Test Database Setup (Rails 7.2+)
**Issue**: `db:migrate` fails or behaves incorrectly with Rails 7.2+ due to schema_migrations table handling.
- Rails 7.2 changed how `schema_migrations` is managed
- `db:schema:load` is faster but doesn't populate `schema_migrations` correctly for Redmine's plugin migration system
- Redmine's `lib/redmine/plugin.rb` queries `schema_migrations` to track plugin versions

**Workaround** (used in `tools/test/test-6.1.0.sh` and `test-7.0.0-dev.sh`):
```bash
bundle exec rake db:create db:schema:load RAILS_ENV=test
sqlite3 db/redmine_test.sqlite3 "CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR(255) NOT NULL UNIQUE PRIMARY KEY);"
sqlite3 db/redmine_test.sqlite3 "CREATE UNIQUE INDEX IF NOT EXISTS unique_schema_migrations ON schema_migrations (version);"
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
```

**Status**: Upstream issue, not fixed as of Jan 2026. See Rails/Redmine compatibility discussions.

### Redmine 5.1.10 Test Database Environment
**Issue**: `db:drop` fails with `ActiveRecord::NoEnvironmentInSchemaError` when the test database lacks environment metadata.
**Workaround**: Run `bundle exec rails db:environment:set RAILS_ENV=test` before `db:drop`.
**Status**: Applied in `tools/test/test-5.1.10.sh`.

### Redmine 7.0+ Native Webhook Conflict
**Issue**: Redmine trunk (7.0-dev) introduces native `class Webhook < ApplicationRecord` in `app/models/webhook.rb`.
- Our plugin uses `module Webhook` as a namespace for table prefix
- This conflicts with native Redmine's class definition
- Redmine 5.1.x and 6.1.x do NOT have native webhooks - plugin is needed

**Strategy**: 
- Plugin detects native webhook support at runtime
- On Redmine 5.1.x / 6.1.x (no native): Use full plugin implementation
- On Redmine 7.0+ (native exists): Plugin remains authoritative; disable or bypass native delivery to avoid duplicates
- Use `RedmineWebhookPlugin::` namespace for all plugin code to avoid conflicts
- Detection method: Check if `defined?(::Webhook) && ::Webhook < ApplicationRecord`

### Redmine 6.1.0 Minitest Compatibility
**Issue**: Rails 7.2 ships with minitest 6.0.1 which has breaking API changes with `line_filtering.rb`.
**Workaround**: Pin minitest to 5.x in `.redmine-test/redmine-6.1.0/Gemfile.local`:
```ruby
gem 'minitest', '~> 5.25'
```

### Redmine 7.0.0+ Test Framework Compatibility
**Status**: Tests now pass on all versions: 5.1.0, 5.1.10, 6.1.0, and 7.0.0-dev. The previous test framework issues with Redmine 7.0.0-dev have been resolved.

Run tests from within Redmine root (plugin at `plugins/redmine_webhook_plugin`):
- All tests: `VERSION=5.1.0 tools/test/run-test.sh` (repeat for 5.1.10/6.1.0/7.0.0-dev) or `cd .redmine-test/redmine-<version> && bundle exec rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test`
- Single test: `cd .redmine-test/redmine-<version> && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/sanity_test.rb -n test_plugin_is_registered`
- CI script: `REDMINE_DIR=.redmine-test/redmine-<version> ./tools/ci/run_redmine_compat.sh`
- Podman testing guide: `docs/podman-testing-guide.md`

---

## Build, Lint, and Test Commands

### Run All Tests (All Versions)
```bash
# Using unified test runner
VERSION=all tools/test/run-test.sh

# Individual versions
VERSION=5.1.0 tools/test/run-test.sh
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
VERSION=7.0.0-dev tools/test/run-test.sh
```

### Run a Single Test File
```bash
# Via unified runner
TESTFILE=payload_builder VERSION=5.1.0 tools/test/run-test.sh

# Direct podman command
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'
```

### Run a Specific Test
```bash
# With test name pattern
bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/payload_builder_test.rb -n "/test_name_pattern/"
```

### Rubocop Linting
```bash
# Via bundle cache
.bundle-cache/6.1.0/ruby/3.2.0/bin/rubocop

# Or install and run
gem install rubocop && rubocop
```

### Start Local Redmine for Manual Testing
```bash
# Development server
tools/dev/start-redmine.sh 5.1.0

# Stop
tools/dev/stop-redmine.sh
```

---

## Code Style Guidelines

### Philosophy
**Modular, Functional, Maintainable**
- Prefer pure functions (same input = same output)
- Create new data, don't mutate existing
- Compose small functions into larger ones
- Keep functions under 50 lines

### Naming Conventions

| Element | Convention | Examples |
|---------|------------|----------|
| Files | snake_case.rb | `payload_builder.rb`, `webhook_delivery.rb` |
| Classes/Modules | PascalCase | `Webhook::PayloadBuilder`, `RedmineWebhookPlugin` |
| Methods | snake_case with verb | `build_envelope`, `serialize_actor` |
| Variables | snake_case, descriptive | `event_data`, `payload_mode` |
| Constants | UPPER_SNAKE_CASE | `SCHEMA_VERSION`, `MAX_PAYLOAD_SIZE` |
| Predicates | `is_`/`has_`/`can_` prefix | `enabled?`, `matches_event?` |
| Private methods | Leading underscore | `def _helper_method; end` |

### Ruby/Rails Patterns

**Constants and Configuration**:
```ruby
# Define constants at class level
SCHEMA_VERSION = "1.0".freeze
MAX_PAYLOAD_SIZE = 1_048_576  # 1MB
SKIP_ATTRIBUTES = %w[updated_on created_on].freeze

# Use frozen strings
DEFAULT_CONFIG = { "key" => "value" }.freeze
```

**Service Objects**:
```ruby
module RedmineWebhookPlugin
  module Webhook
    class PayloadBuilder
      attr_reader :event_data, :payload_mode

      def initialize(event_data, payload_mode = "minimal")
        validate_inputs!(event_data, payload_mode)
        @event_data = event_data
        @payload_mode = payload_mode
      end

      def build
        # Return hash for JSON serialization
      end

      private

      def validate_inputs!(event_data, payload_mode)
        raise ArgumentError, "event_data must be a Hash" unless event_data.is_a?(Hash)
        # More validations...
      end
    end
  end
end
```

**ActiveRecord Models**:
```ruby
module RedmineWebhookPlugin
  module Webhook
    class Endpoint < ActiveRecord::Base
      self.table_name = "webhook_endpoints"

      belongs_to :webhook_user, class_name: "User", optional: true
      has_many :deliveries, class_name: "RedmineWebhookPlugin::Webhook::Delivery",
                           foreign_key: :endpoint_id, dependent: :nullify

      validates :name, presence: true, uniqueness: true
      validates :url, presence: true

      scope :enabled, -> { where(enabled: true) }

      # Instance methods
      def matches_event?(event_type, action, project_id)
        # Implementation
      end

      # Custom JSON attribute accessors
      def events_config
        JSON.parse(read_attribute(:events_config) || "{}")
      end

      def events_config=(hash)
        write_attribute(:events_config, hash.to_json)
      end
    end
  end
end
```

### Error Handling

```ruby
# ✅ Prefer explicit error handling
def build
  payload = build_envelope
  payload[:actor] = serialize_actor(event_data[:actor])
  enforce_size_limit(payload)
rescue PayloadTooLargeError => e
  # Handle or re-raise with context
  raise PayloadTooLargeError, "Payload exceeds #{MAX_PAYLOAD_SIZE} bytes"
end

# ✅ Validate at boundaries
def initialize(event_data, payload_mode = "minimal")
  raise ArgumentError, "event_data must be a Hash" unless event_data.is_a?(Hash)
  raise ArgumentError, "event_type is required" unless event_data[:event_type].present?
  # ...
end

# ✅ Custom error classes
class PayloadTooLargeError < StandardError; end
```

### Immutability and Purity

```ruby
# ✅ Return new objects
def serialize_actor(user)
  return nil if user.nil?
  { id: user.id, login: user.login, name: user.name }
end

# ❌ Don't mutate inputs
def update_user(user, changes)
  user.update!(changes)  # Bad - side effect
end
```

### Hash and Array Patterns

```ruby
# ✅ Use symbol keys
{ event_id: event_data[:event_id], event_type: event_data[:event_type] }

# ✅ Freeze constants
SENSITIVE_FIELDS = %w[api_key password secret].freeze

# ✅ Use presence check
saved_changes = event_data[:saved_changes].presence || event_data[:changes]

# ✅ Safe navigation for nested access
payload[:issue]&.[:custom_fields]
```

### Controller Patterns

```ruby
class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update, :destroy]

  def index
    @endpoints = Webhook::Endpoint.order(:name)
  end

  def create
    @endpoint = Webhook::Endpoint.new(endpoint_params)
    if @endpoint.save
      redirect_to admin_webhook_endpoints_path
    else
      render :new
    end
  end

  private

  def find_endpoint
    @endpoint = Webhook::Endpoint.find(params[:id])
  end

  def endpoint_params
    params.require(:webhook_endpoint).permit(:name, :url, :enabled, :payload_mode)
  end
end
```

### Model Patches (Rails Concerns)

```ruby
module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = User.current
      end

      def webhook_after_create
        return if @webhook_skip
        # Dispatch event...
      end
    end
  end
end
```

---

## Testing Patterns

```ruby
require File.expand_path("../../test_helper", __dir__)

class Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  test "build includes envelope fields" do
    event_id = SecureRandom.uuid
    event_data = {
      event_id: event_id,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1)
    }
    builder = Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_equal event_id, result[:event_id]
    assert_equal "issue", result[:event_type]
    assert_kind_of Hash, result[:actor]
  end
end
```

---

## Key File Locations

| Purpose | Location |
|---------|----------|
| Services | `app/services/webhook/` |
| Models | `app/models/redmine_webhook_plugin/webhook/` |
| Controllers | `app/controllers/admin/` |
| Views | `app/views/admin/` |
| Tests | `test/unit/`, `test/functional/` |
| Migrations | `db/migrate/` |
| Routes | `config/routes.rb` |
| Localization | `config/locales/` |

---

## Compatibility Notes

- Redmine 7.0+ has native webhooks; the plugin detects and disables native delivery
- Use `RedmineWebhookPlugin::` namespace to avoid conflicts
- Support Redmine >= 5.1.0 (tested on 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)
- Test all features on multiple Redmine versions before marking complete

## Commit Guidelines
- Subjects: `<area>: <summary>` (e.g., `feat:`, `fix:`, `ci:`, `docs:`)
- CI must pass across 5.1.0 / 5.1.10 / 6.1.0 / 7.0.0.0-dev  matrix

## Update CHANGELOG
- Everytimes you add features, change request, fix , bugfix , update the CHANGELOG.md
