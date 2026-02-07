# Workstream D: Delivery Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the HTTP delivery infrastructure that sends webhook payloads to endpoints, handles errors, retries with exponential backoff, and manages API key authentication.

**Architecture:** Service objects under `app/services/webhook/` namespace. HttpClient handles the actual HTTP POST using Net::HTTP. ErrorClassifier maps exceptions to error codes. RetryPolicy calculates backoff delays. ApiKeyResolver fetches/generates user API keys. HeadersBuilder constructs request headers. DeliveryResult is a value object encapsulating success/failure outcomes.

**Tech Stack:** Ruby/Rails, Net::HTTP, OpenSSL, Redmine Plugin API, Minitest

**Depends on:** P0 Foundation complete (RedmineWebhookPlugin::Webhook::Endpoint and RedmineWebhookPlugin::Webhook::Delivery models exist)

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

## Task 1: Create DeliveryResult Value Object

**Files:**
- Create: `app/services/webhook/delivery_result.rb`
- Test: `test/unit/webhook/delivery_result_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/delivery_result_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DeliveryResultTest < ActiveSupport::TestCase
  test "DeliveryResult class exists" do
    assert defined?(RedmineWebhookPlugin::Webhook::DeliveryResult), "RedmineWebhookPlugin::Webhook::DeliveryResult should be defined"
  end

  test "success factory creates successful result" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(
      http_status: 200,
      response_body: '{"ok":true}',
      duration_ms: 150,
      final_url: "https://example.com/webhook"
    )

    assert result.success?
    assert_not result.failure?
    assert_equal 200, result.http_status
    assert_equal '{"ok":true}', result.response_body
    assert_equal 150, result.duration_ms
    assert_equal "https://example.com/webhook", result.final_url
    assert_nil result.error_code
  end

  test "failure factory creates failed result" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.failure(
      error_code: "connection_timeout",
      error_message: "Connection timed out after 30s",
      duration_ms: 30000
    )

    assert_not result.success?
    assert result.failure?
    assert_equal "connection_timeout", result.error_code
    assert_equal "Connection timed out after 30s", result.error_message
    assert_equal 30000, result.duration_ms
    assert_nil result.http_status
  end

  test "failure with http_status" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.failure(
      error_code: "http_error",
      http_status: 500,
      response_body: "Internal Server Error",
      duration_ms: 100
    )

    assert result.failure?
    assert_equal 500, result.http_status
    assert_equal "http_error", result.error_code
    assert_equal "Internal Server Error", result.response_body
  end

  test "response_body_excerpt truncates to 2KB" do
    long_body = "x" * 5000
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(
      http_status: 200,
      response_body: long_body,
      duration_ms: 100
    )

    assert_equal 2048, result.response_body_excerpt.length
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_result_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::DeliveryResult"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/delivery_result.rb
module RedmineWebhookPlugin::Webhook
  class DeliveryResult
    MAX_BODY_EXCERPT = 2048

    attr_reader :http_status, :response_body, :error_code, :error_message,
                :duration_ms, :final_url

    def initialize(success:, http_status: nil, response_body: nil, error_code: nil,
                   error_message: nil, duration_ms: nil, final_url: nil)
      @success = success
      @http_status = http_status
      @response_body = response_body
      @error_code = error_code
      @error_message = error_message
      @duration_ms = duration_ms
      @final_url = final_url
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def response_body_excerpt
      return nil if @response_body.nil?

      @response_body.to_s[0, MAX_BODY_EXCERPT]
    end

    def self.success(http_status:, response_body: nil, duration_ms:, final_url: nil)
      new(
        success: true,
        http_status: http_status,
        response_body: response_body,
        duration_ms: duration_ms,
        final_url: final_url
      )
    end

    def self.failure(error_code:, error_message: nil, http_status: nil,
                     response_body: nil, duration_ms: nil)
      new(
        success: false,
        error_code: error_code,
        error_message: error_message,
        http_status: http_status,
        response_body: response_body,
        duration_ms: duration_ms
      )
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
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_result_test.rb -v'
```

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_result_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/delivery_result_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 7: Commit**

```bash
git add app/services/webhook/delivery_result.rb test/unit/webhook/delivery_result_test.rb init.rb
git commit -m "feat(d): add DeliveryResult value object"
```

---

## Task 2: Create ErrorClassifier Service

**Files:**
- Create: `app/services/webhook/error_classifier.rb`
- Test: `test/unit/webhook/error_classifier_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/error_classifier_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::ErrorClassifierTest < ActiveSupport::TestCase
  test "ErrorClassifier class exists" do
    assert defined?(RedmineWebhookPlugin::Webhook::ErrorClassifier), "RedmineWebhookPlugin::Webhook::ErrorClassifier should be defined"
  end

  test "classifies Timeout::Error as connection_timeout" do
    error = Timeout::Error.new("execution expired")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "connection_timeout", result
  end

  test "classifies Net::OpenTimeout as connection_timeout" do
    error = Net::OpenTimeout.new("connection timed out")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "connection_timeout", result
  end

  test "classifies Net::ReadTimeout as read_timeout" do
    error = Net::ReadTimeout.new("read timed out")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "read_timeout", result
  end

  test "classifies Errno::ECONNREFUSED as connection_refused" do
    error = Errno::ECONNREFUSED.new("Connection refused")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "connection_refused", result
  end

  test "classifies Errno::ECONNRESET as connection_reset" do
    error = Errno::ECONNRESET.new("Connection reset")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "connection_reset", result
  end

  test "classifies SocketError as dns_error" do
    error = SocketError.new("getaddrinfo: Name or service not known")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "dns_error", result
  end

  test "classifies OpenSSL::SSL::SSLError as ssl_error" do
    error = OpenSSL::SSL::SSLError.new("certificate verify failed")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "ssl_error", result
  end

  test "classifies 4xx HTTP status as http_client_error" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(400)
    assert_equal "http_client_error", result

    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(404)
    assert_equal "http_client_error", result

    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(429)
    assert_equal "http_client_error", result
  end

  test "classifies 5xx HTTP status as http_server_error" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(500)
    assert_equal "http_server_error", result

    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(503)
    assert_equal "http_server_error", result
  end

  test "classifies 2xx HTTP status as nil (success)" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(200)
    assert_nil result

    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(201)
    assert_nil result
  end

  test "classifies unknown exception as unknown_error" do
    error = StandardError.new("Something unexpected")
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(error)

    assert_equal "unknown_error", result
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/error_classifier_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::ErrorClassifier"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/error_classifier.rb
require "openssl"
require "net/http"

module RedmineWebhookPlugin::Webhook
  class ErrorClassifier
    EXCEPTION_MAP = {
      Timeout::Error => "connection_timeout",
      Net::OpenTimeout => "connection_timeout",
      Net::ReadTimeout => "read_timeout",
      Errno::ECONNREFUSED => "connection_refused",
      Errno::ECONNRESET => "connection_reset",
      Errno::EHOSTUNREACH => "host_unreachable",
      Errno::ENETUNREACH => "network_unreachable",
      SocketError => "dns_error",
      OpenSSL::SSL::SSLError => "ssl_error"
    }.freeze

    def self.classify(exception)
      EXCEPTION_MAP.each do |klass, code|
        return code if exception.is_a?(klass)
      end
      "unknown_error"
    end

    def self.classify_http_status(status)
      case status
      when 200..299
        nil
      when 400..499
        "http_client_error"
      when 500..599
        "http_server_error"
      else
        "http_unknown_status"
      end
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
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/error_classifier_test.rb -v'
```

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/error_classifier_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/error_classifier_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 12 tests, 0 failures

**Step 7: Commit**

```bash
git add app/services/webhook/error_classifier.rb test/unit/webhook/error_classifier_test.rb init.rb
git commit -m "feat(d): add ErrorClassifier service"
```

---

## Task 3: Create RetryPolicy Service - Basic Structure

**Files:**
- Create: `app/services/webhook/retry_policy.rb`
- Test: `test/unit/webhook/retry_policy_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/retry_policy_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::RetryPolicyTest < ActiveSupport::TestCase
  test "RetryPolicy class exists" do
    assert defined?(RedmineWebhookPlugin::Webhook::RetryPolicy), "RedmineWebhookPlugin::Webhook::RetryPolicy should be defined"
  end

  test "initializes with default config" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal 5, policy.max_attempts
    assert_equal 60, policy.base_delay
    assert_equal 3600, policy.max_delay
    assert_includes policy.retryable_statuses, 500
    assert_includes policy.retryable_statuses, 502
    assert_includes policy.retryable_statuses, 503
  end

  test "initializes with custom config" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(
      "max_attempts" => 3,
      "base_delay" => 30,
      "max_delay" => 1800,
      "retryable_statuses" => [500, 503]
    )

    assert_equal 3, policy.max_attempts
    assert_equal 30, policy.base_delay
    assert_equal 1800, policy.max_delay
    assert_equal [500, 503], policy.retryable_statuses
  end

  test "accepts symbol keys" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(
      max_attempts: 10,
      base_delay: 120
    )

    assert_equal 10, policy.max_attempts
    assert_equal 120, policy.base_delay
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::RetryPolicy"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/retry_policy.rb
module RedmineWebhookPlugin::Webhook
  class RetryPolicy
    DEFAULT_CONFIG = {
      "max_attempts" => 5,
      "base_delay" => 60,
      "max_delay" => 3600,
      "retryable_statuses" => [408, 429, 500, 502, 503, 504]
    }.freeze

    attr_reader :max_attempts, :base_delay, :max_delay, :retryable_statuses

    def initialize(config = {})
      config = config.transform_keys(&:to_s)
      merged = DEFAULT_CONFIG.merge(config)

      @max_attempts = merged["max_attempts"].to_i
      @base_delay = merged["base_delay"].to_i
      @max_delay = merged["max_delay"].to_i
      @retryable_statuses = Array(merged["retryable_statuses"]).map(&:to_i)
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
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/retry_policy", __FILE__)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 7: Commit**

```bash
git add app/services/webhook/retry_policy.rb test/unit/webhook/retry_policy_test.rb init.rb
git commit -m "feat(d): add RetryPolicy service basic structure"
```

---

## Task 4: RetryPolicy - Retryable Logic

**Files:**
- Modify: `app/services/webhook/retry_policy.rb`
- Modify: `test/unit/webhook/retry_policy_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/retry_policy_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::RetryPolicyTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "retryable? returns true for retryable HTTP status" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert policy.retryable?(http_status: 500)
    assert policy.retryable?(http_status: 502)
    assert policy.retryable?(http_status: 503)
    assert policy.retryable?(http_status: 429)
  end

  test "retryable? returns false for non-retryable HTTP status" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_not policy.retryable?(http_status: 200)
    assert_not policy.retryable?(http_status: 400)
    assert_not policy.retryable?(http_status: 401)
    assert_not policy.retryable?(http_status: 404)
  end

  test "retryable? returns true for network errors" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert policy.retryable?(error_code: "connection_timeout")
    assert policy.retryable?(error_code: "connection_refused")
    assert policy.retryable?(error_code: "connection_reset")
    assert policy.retryable?(error_code: "dns_error")
    assert policy.retryable?(error_code: "read_timeout")
  end

  test "retryable? returns false for SSL errors (ssl_verify enabled)" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_not policy.retryable?(error_code: "ssl_error", ssl_verify: true)
  end

  test "retryable? returns true for SSL errors when ssl_verify disabled" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert policy.retryable?(error_code: "ssl_error", ssl_verify: false)
  end

  test "should_retry? considers attempt count" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("max_attempts" => 3)

    assert policy.should_retry?(attempt_count: 0, error_code: "connection_timeout")
    assert policy.should_retry?(attempt_count: 1, error_code: "connection_timeout")
    assert policy.should_retry?(attempt_count: 2, error_code: "connection_timeout")
    assert_not policy.should_retry?(attempt_count: 3, error_code: "connection_timeout")
    assert_not policy.should_retry?(attempt_count: 5, error_code: "connection_timeout")
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```


Expected: FAIL - retryable? and should_retry? methods not defined

**Step 3: Add retryable logic**

```ruby
# app/services/webhook/retry_policy.rb
module RedmineWebhookPlugin::Webhook
  class RetryPolicy
    DEFAULT_CONFIG = {
      "max_attempts" => 5,
      "base_delay" => 60,
      "max_delay" => 3600,
      "retryable_statuses" => [408, 429, 500, 502, 503, 504]
    }.freeze

    RETRYABLE_ERROR_CODES = %w[
      connection_timeout
      read_timeout
      connection_refused
      connection_reset
      host_unreachable
      network_unreachable
      dns_error
    ].freeze

    attr_reader :max_attempts, :base_delay, :max_delay, :retryable_statuses

    def initialize(config = {})
      config = config.transform_keys(&:to_s)
      merged = DEFAULT_CONFIG.merge(config)

      @max_attempts = merged["max_attempts"].to_i
      @base_delay = merged["base_delay"].to_i
      @max_delay = merged["max_delay"].to_i
      @retryable_statuses = Array(merged["retryable_statuses"]).map(&:to_i)
    end

    def retryable?(http_status: nil, error_code: nil, ssl_verify: true)
      return true if http_status && retryable_statuses.include?(http_status.to_i)
      return true if error_code && RETRYABLE_ERROR_CODES.include?(error_code.to_s)
      return true if error_code == "ssl_error" && !ssl_verify

      false
    end

    def should_retry?(attempt_count:, http_status: nil, error_code: nil, ssl_verify: true)
      return false if attempt_count >= max_attempts

      retryable?(http_status: http_status, error_code: error_code, ssl_verify: ssl_verify)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 10 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/retry_policy.rb test/unit/webhook/retry_policy_test.rb
git commit -m "feat(d): add RetryPolicy retryable? and should_retry? methods"
```

---

## Task 5: RetryPolicy - Backoff Calculator

**Files:**
- Modify: `app/services/webhook/retry_policy.rb`
- Modify: `test/unit/webhook/retry_policy_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/retry_policy_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::RetryPolicyTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "next_delay calculates exponential backoff" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("base_delay" => 60, "max_delay" => 3600)

    # Without jitter, delays double each attempt
    assert_equal 60, policy.next_delay(0, jitter: false)
    assert_equal 120, policy.next_delay(1, jitter: false)
    assert_equal 240, policy.next_delay(2, jitter: false)
    assert_equal 480, policy.next_delay(3, jitter: false)
  end

  test "next_delay respects max_delay cap" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("base_delay" => 60, "max_delay" => 300)

    assert_equal 60, policy.next_delay(0, jitter: false)
    assert_equal 120, policy.next_delay(1, jitter: false)
    assert_equal 240, policy.next_delay(2, jitter: false)
    assert_equal 300, policy.next_delay(3, jitter: false)
    assert_equal 300, policy.next_delay(10, jitter: false)
  end

  test "next_delay with jitter stays within range" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("base_delay" => 100, "max_delay" => 3600)

    100.times do
      delay = policy.next_delay(0, jitter: true)
      # Base is 100, jitter is 0.8-1.2 range, so 80-120
      assert delay >= 80, "Delay #{delay} should be >= 80"
      assert delay <= 120, "Delay #{delay} should be <= 120"
    end
  end

  test "next_retry_at returns Time" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("base_delay" => 60)

    now = Time.current
    retry_at = policy.next_retry_at(0, jitter: false)

    assert_kind_of Time, retry_at
    assert retry_at >= now + 59.seconds
    assert retry_at <= now + 61.seconds
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```


Expected: FAIL - next_delay and next_retry_at methods not defined

**Step 3: Add backoff calculator**

```ruby
# app/services/webhook/retry_policy.rb - add methods to class
module RedmineWebhookPlugin::Webhook
  class RetryPolicy
    # ... existing constants and methods ...

    def next_delay(attempt_count, jitter: true)
      raw_delay = base_delay * (2 ** attempt_count)
      capped_delay = [raw_delay, max_delay].min

      if jitter
        apply_jitter(capped_delay)
      else
        capped_delay
      end
    end

    def next_retry_at(attempt_count, jitter: true)
      Time.current + next_delay(attempt_count, jitter: jitter).seconds
    end

    private

    def apply_jitter(delay)
      # Jitter factor between 0.8 and 1.2
      jitter_factor = 0.8 + (rand * 0.4)
      (delay * jitter_factor).round
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/retry_policy_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 14 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/retry_policy.rb test/unit/webhook/retry_policy_test.rb
git commit -m "feat(d): add RetryPolicy exponential backoff with jitter"
```

---

## Task 6: Create ApiKeyResolver Service - Basic Lookup

**Files:**
- Create: `app/services/webhook/api_key_resolver.rb`
- Test: `test/unit/webhook/api_key_resolver_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/api_key_resolver_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::ApiKeyResolverTest < ActiveSupport::TestCase
  def setup
    @user = User.find(2) # existing user from fixtures
  end

  test "ApiKeyResolver class exists" do
    assert defined?(RedmineWebhookPlugin::Webhook::ApiKeyResolver), "RedmineWebhookPlugin::Webhook::ApiKeyResolver should be defined"
  end

  test "resolve returns existing API key for user" do
    # Create an API token for the user
    token = Token.create!(user: @user, action: "api")

    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(@user.id)

    assert_equal token.value, result
  end

  test "resolve returns nil when user has no API key" do
    # Ensure no API token exists
    Token.where(user_id: @user.id, action: "api").delete_all

    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(@user.id)

    assert_nil result
  end

  test "resolve returns nil for non-existent user" do
    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(999999)

    assert_nil result
  end

  test "resolve accepts User object" do
    token = Token.create!(user: @user, action: "api")

    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(@user)

    assert_equal token.value, result
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::ApiKeyResolver"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/api_key_resolver.rb
module RedmineWebhookPlugin::Webhook
  class ApiKeyResolver
    def self.resolve(user_or_id)
      user = find_user(user_or_id)
      return nil unless user

      token = Token.find_by(user_id: user.id, action: "api")
      token&.value
    end

    def self.find_user(user_or_id)
      case user_or_id
      when User
        user_or_id
      when Integer
        User.find_by(id: user_or_id)
      else
        nil
      end
    end

    private_class_method :find_user
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
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/retry_policy", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/api_key_resolver", __FILE__)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 7: Commit**

```bash
git add app/services/webhook/api_key_resolver.rb test/unit/webhook/api_key_resolver_test.rb init.rb
git commit -m "feat(d): add ApiKeyResolver service with basic lookup"
```

---

## Task 7: ApiKeyResolver - Auto-Generation

**Files:**
- Modify: `app/services/webhook/api_key_resolver.rb`
- Modify: `test/unit/webhook/api_key_resolver_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/api_key_resolver_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::ApiKeyResolverTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "generate_if_missing creates new API key when none exists" do
    Token.where(user_id: @user.id, action: "api").delete_all

    # Enable REST API
    with_settings(rest_api_enabled: "1") do
      result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(@user)

      assert_not_nil result
      assert Token.exists?(user_id: @user.id, action: "api")
    end
  end

  test "generate_if_missing returns existing key if present" do
    existing_token = Token.create!(user: @user, action: "api")

    with_settings(rest_api_enabled: "1") do
      result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(@user)

      assert_equal existing_token.value, result
      assert_equal 1, Token.where(user_id: @user.id, action: "api").count
    end
  end

  test "generate_if_missing raises error when REST API disabled" do
    Token.where(user_id: @user.id, action: "api").delete_all

    with_settings(rest_api_enabled: "0") do
      assert_raises(RedmineWebhookPlugin::Webhook::ApiKeyResolver::RestApiDisabledError) do
        RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(@user)
      end
    end
  end

  test "generate_if_missing raises error for invalid user" do
    assert_raises(RedmineWebhookPlugin::Webhook::ApiKeyResolver::UserNotFoundError) do
      RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(999999)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```


Expected: FAIL - generate_if_missing method and error classes not defined

**Step 3: Add auto-generation**

```ruby
# app/services/webhook/api_key_resolver.rb
module RedmineWebhookPlugin::Webhook
  class ApiKeyResolver
    class RestApiDisabledError < StandardError; end
    class UserNotFoundError < StandardError; end

    def self.resolve(user_or_id)
      user = find_user(user_or_id)
      return nil unless user

      token = Token.find_by(user_id: user.id, action: "api")
      token&.value
    end

    def self.generate_if_missing(user_or_id)
      user = find_user(user_or_id)
      raise UserNotFoundError, "User not found" unless user

      existing = resolve(user)
      return existing if existing

      raise RestApiDisabledError, "REST API is disabled" unless rest_api_enabled?

      token = Token.create!(user: user, action: "api")
      token.value
    end

    def self.rest_api_enabled?
      Setting.rest_api_enabled?
    end

    def self.find_user(user_or_id)
      case user_or_id
      when User
        user_or_id
      when Integer
        User.find_by(id: user_or_id)
      else
        nil
      end
    end

    private_class_method :find_user, :rest_api_enabled?
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 9 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/api_key_resolver.rb test/unit/webhook/api_key_resolver_test.rb
git commit -m "feat(d): add ApiKeyResolver auto-generation with REST API check"
```

---

## Task 8: ApiKeyResolver - Fingerprinting

**Files:**
- Modify: `app/services/webhook/api_key_resolver.rb`
- Modify: `test/unit/webhook/api_key_resolver_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/api_key_resolver_test.rb - add to existing file
require "digest"

class RedmineWebhookPlugin::Webhook::ApiKeyResolverTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "fingerprint returns SHA256 hash of API key" do
    api_key = "test-api-key-12345"
    expected = Digest::SHA256.hexdigest(api_key)

    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(api_key)

    assert_equal expected, result
    assert_equal 64, result.length # SHA256 produces 64 hex chars
  end

  test "fingerprint returns 'missing' for nil key" do
    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(nil)

    assert_equal "missing", result
  end

  test "fingerprint returns 'missing' for empty string" do
    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint("")

    assert_equal "missing", result
  end

  test "fingerprint returns consistent hash for same key" do
    api_key = "consistent-key-test"

    result1 = RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(api_key)
    result2 = RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(api_key)

    assert_equal result1, result2
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```


Expected: FAIL - fingerprint method not defined

**Step 3: Add fingerprinting**

```ruby
# app/services/webhook/api_key_resolver.rb - add to top of file and class
require "digest"

module RedmineWebhookPlugin::Webhook
  class ApiKeyResolver
    class RestApiDisabledError < StandardError; end
    class UserNotFoundError < StandardError; end

    MISSING_FINGERPRINT = "missing".freeze

    def self.resolve(user_or_id)
      user = find_user(user_or_id)
      return nil unless user

      token = Token.find_by(user_id: user.id, action: "api")
      token&.value
    end

    def self.generate_if_missing(user_or_id)
      user = find_user(user_or_id)
      raise UserNotFoundError, "User not found" unless user

      existing = resolve(user)
      return existing if existing

      raise RestApiDisabledError, "REST API is disabled" unless rest_api_enabled?

      token = Token.create!(user: user, action: "api")
      token.value
    end

    def self.fingerprint(api_key)
      return MISSING_FINGERPRINT if api_key.nil? || api_key.to_s.empty?

      Digest::SHA256.hexdigest(api_key.to_s)
    end

    def self.rest_api_enabled?
      Setting.rest_api_enabled?
    end

    def self.find_user(user_or_id)
      case user_or_id
      when User
        user_or_id
      when Integer
        User.find_by(id: user_or_id)
      else
        nil
      end
    end

    private_class_method :find_user, :rest_api_enabled?
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/api_key_resolver_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 13 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/api_key_resolver.rb test/unit/webhook/api_key_resolver_test.rb
git commit -m "feat(d): add ApiKeyResolver fingerprinting with SHA256"
```

---

## Task 9: Create HeadersBuilder Service

**Files:**
- Create: `app/services/webhook/headers_builder.rb`
- Test: `test/unit/webhook/headers_builder_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/headers_builder_test.rb
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::HeadersBuilderTest < ActiveSupport::TestCase
  test "HeadersBuilder class exists" do
    assert defined?(RedmineWebhookPlugin::Webhook::HeadersBuilder), "RedmineWebhookPlugin::Webhook::HeadersBuilder should be defined"
  end

  test "build includes Content-Type header" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(event_id: "test-123")

    assert_equal "application/json; charset=utf-8", headers["Content-Type"]
  end

  test "build includes User-Agent with plugin and Redmine versions" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(event_id: "test-123")

    assert_match %r{RedmineWebhook/[\d.]+}, headers["User-Agent"]
    assert_match %r{Redmine/[\d.]+}, headers["User-Agent"]
  end

  test "build includes X-Redmine-Event-ID" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(event_id: "uuid-12345")

    assert_equal "uuid-12345", headers["X-Redmine-Event-ID"]
  end

  test "build includes X-Redmine-Event with event type and action" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "test-123",
      event_type: "issue",
      action: "created"
    )

    assert_equal "issue.created", headers["X-Redmine-Event"]
  end

  test "build includes X-Redmine-API-Key when provided" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "test-123",
      api_key: "secret-api-key"
    )

    assert_equal "secret-api-key", headers["X-Redmine-API-Key"]
  end

  test "build excludes X-Redmine-API-Key when nil" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "test-123",
      api_key: nil
    )

    assert_not headers.key?("X-Redmine-API-Key")
  end

  test "build includes X-Redmine-Delivery for delivery tracking" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "test-123",
      delivery_id: 42
    )

    assert_equal "42", headers["X-Redmine-Delivery"]
  end

  test "build merges custom headers" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "test-123",
      custom_headers: { "X-Custom" => "value", "Authorization" => "Bearer token" }
    )

    assert_equal "value", headers["X-Custom"]
    assert_equal "Bearer token", headers["Authorization"]
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/headers_builder_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::HeadersBuilder"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/headers_builder.rb
module RedmineWebhookPlugin::Webhook
  class HeadersBuilder
    CONTENT_TYPE = "application/json; charset=utf-8".freeze

    def self.build(event_id:, event_type: nil, action: nil, api_key: nil,
                   delivery_id: nil, custom_headers: {})
      headers = {
        "Content-Type" => CONTENT_TYPE,
        "User-Agent" => user_agent,
        "X-Redmine-Event-ID" => event_id.to_s
      }

      if event_type && action
        headers["X-Redmine-Event"] = "#{event_type}.#{action}"
      end

      headers["X-Redmine-API-Key"] = api_key if api_key.present?
      headers["X-Redmine-Delivery"] = delivery_id.to_s if delivery_id

      headers.merge(custom_headers.to_h)
    end

    def self.user_agent
      plugin_version = plugin_info&.version || "0.0.0"
      redmine_version = Redmine::VERSION.to_s

      "RedmineWebhook/#{plugin_version} (Redmine/#{redmine_version})"
    end

    def self.plugin_info
      Redmine::Plugin.find(:redmine_webhook_plugin)
    rescue Redmine::PluginNotFound
      nil
    end

    private_class_method :user_agent, :plugin_info
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
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/retry_policy", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/api_key_resolver", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/headers_builder", __FILE__)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/headers_builder_test.rb -v'
```

**Step 6: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/headers_builder_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/headers_builder_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 9 tests, 0 failures

**Step 7: Commit**

```bash
git add app/services/webhook/headers_builder.rb test/unit/webhook/headers_builder_test.rb init.rb
git commit -m "feat(d): add HeadersBuilder service"
```

---

## Task 10: Create HttpClient Service - Basic Structure

**Files:**
- Create: `app/services/webhook/http_client.rb`
- Test: `test/unit/webhook/http_client_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook/http_client_test.rb
require File.expand_path("../../test_helper", __dir__)
require "webmock/minitest"

class RedmineWebhookPlugin::Webhook::HttpClientTest < ActiveSupport::TestCase
  def setup
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.allow_net_connect!
  end

  test "HttpClient class exists" do
    assert defined?(RedmineWebhookPlugin::Webhook::HttpClient), "RedmineWebhookPlugin::Webhook::HttpClient should be defined"
  end

  test "initializes with endpoint config" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(
      timeout: 30,
      ssl_verify: true
    )

    assert_equal 30, client.timeout
    assert_equal true, client.ssl_verify
  end

  test "initializes with default config" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new

    assert_equal 30, client.timeout
    assert_equal true, client.ssl_verify
  end

  test "post makes HTTP POST request" do
    stub_request(:post, "https://example.com/webhook")
      .with(
        body: '{"test":"data"}',
        headers: { "Content-Type" => "application/json" }
      )
      .to_return(status: 200, body: '{"ok":true}')

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/webhook",
      payload: '{"test":"data"}',
      headers: { "Content-Type" => "application/json" }
    )

    assert result.success?
    assert_equal 200, result.http_status
    assert_equal '{"ok":true}', result.response_body
  end

  test "post returns failure for 5xx response" do
    stub_request(:post, "https://example.com/webhook")
      .to_return(status: 500, body: "Internal Server Error")

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/webhook",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal 500, result.http_status
    assert_equal "http_server_error", result.error_code
  end

  test "post returns failure for 4xx response" do
    stub_request(:post, "https://example.com/webhook")
      .to_return(status: 404, body: "Not Found")

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/webhook",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal 404, result.http_status
    assert_equal "http_client_error", result.error_code
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```


Expected: FAIL with "uninitialized constant RedmineWebhookPlugin::Webhook::HttpClient"

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/http_client.rb
require "net/http"
require "uri"
require "openssl"

module RedmineWebhookPlugin::Webhook
  class HttpClient
    DEFAULT_TIMEOUT = 30
    DEFAULT_SSL_VERIFY = true

    attr_reader :timeout, :ssl_verify

    def initialize(timeout: DEFAULT_TIMEOUT, ssl_verify: DEFAULT_SSL_VERIFY)
      @timeout = timeout
      @ssl_verify = ssl_verify
    end

    def post(url:, payload:, headers:)
      uri = URI.parse(url)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      response = execute_request(uri, payload, headers)
      duration_ms = calculate_duration(start_time)

      build_result(response, duration_ms, url)
    rescue StandardError => e
      duration_ms = calculate_duration(start_time)
      build_error_result(e, duration_ms)
    end

    private

    def execute_request(uri, payload, headers)
      http = build_http(uri)
      request = build_post_request(uri, payload, headers)

      http.request(request)
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      if http.use_ssl?
        http.verify_mode = ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      end

      http
    end

    def build_post_request(uri, payload, headers)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = payload
      headers.each { |key, value| request[key] = value }
      request
    end

    def calculate_duration(start_time)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    end

    def build_result(response, duration_ms, url)
      status = response.code.to_i
      error_code = ErrorClassifier.classify_http_status(status)

      if error_code
        DeliveryResult.failure(
          error_code: error_code,
          http_status: status,
          response_body: response.body,
          duration_ms: duration_ms
        )
      else
        DeliveryResult.success(
          http_status: status,
          response_body: response.body,
          duration_ms: duration_ms,
          final_url: url
        )
      end
    end

    def build_error_result(exception, duration_ms)
      DeliveryResult.failure(
        error_code: ErrorClassifier.classify(exception),
        error_message: exception.message,
        duration_ms: duration_ms
      )
    end
  end
end
```

**Step 4: Add webmock to test dependencies**

Add to your Gemfile (or use conditionally in test_helper.rb):

```ruby
# In test/test_helper.rb, add at the top:
require "webmock/minitest"
```

**Step 5: Update init.rb to require the service**

```ruby
# init.rb - add to the to_prepare block
Rails.application.config.to_prepare do
  require_dependency File.expand_path("../app/models/webhook", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/endpoint", __FILE__)
  require_dependency File.expand_path("../app/models/webhook/delivery", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/retry_policy", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/api_key_resolver", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/headers_builder", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/http_client", __FILE__)
end
```

**Step 6: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```

**Step 7: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 7 tests, 0 failures

**Step 8: Commit**

```bash
git add app/services/webhook/http_client.rb test/unit/webhook/http_client_test.rb init.rb
git commit -m "feat(d): add HttpClient service with basic POST"
```

---

## Task 11: HttpClient - Timeout Handling

**Files:**
- Modify: `app/services/webhook/http_client.rb`
- Modify: `test/unit/webhook/http_client_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/http_client_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::HttpClientTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "post handles connection timeout" do
    stub_request(:post, "https://example.com/webhook")
      .to_timeout

    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 5)
    result = client.post(
      url: "https://example.com/webhook",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal "connection_timeout", result.error_code
    assert_not_nil result.duration_ms
  end

  test "post handles connection refused" do
    stub_request(:post, "https://example.com/webhook")
      .to_raise(Errno::ECONNREFUSED.new("Connection refused"))

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/webhook",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal "connection_refused", result.error_code
  end

  test "post handles DNS error" do
    stub_request(:post, "https://nonexistent.invalid/webhook")
      .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://nonexistent.invalid/webhook",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal "dns_error", result.error_code
  end

  test "post handles SSL error" do
    stub_request(:post, "https://example.com/webhook")
      .to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))

    client = RedmineWebhookPlugin::Webhook::HttpClient.new(ssl_verify: true)
    result = client.post(
      url: "https://example.com/webhook",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal "ssl_error", result.error_code
  end

  test "post captures error message" do
    stub_request(:post, "https://example.com/webhook")
      .to_raise(Errno::ECONNREFUSED.new("Connection refused - connect(2)"))

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/webhook",
      payload: "{}",
      headers: {}
    )

    assert_match(/Connection refused/, result.error_message)
  end
end
```

**Step 2: Run test to verify it passes (already implemented)**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```

**Step 3: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 12 tests, 0 failures (error handling already in place from Task 10)

**Step 4: Commit**

```bash
git add test/unit/webhook/http_client_test.rb
git commit -m "test(d): add HttpClient timeout and error handling tests"
```

---

## Task 12: HttpClient - Redirect Following

**Files:**
- Modify: `app/services/webhook/http_client.rb`
- Modify: `test/unit/webhook/http_client_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/http_client_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::HttpClientTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "post follows 301 redirect" do
    stub_request(:post, "https://example.com/old")
      .to_return(status: 301, headers: { "Location" => "https://example.com/new" })

    stub_request(:post, "https://example.com/new")
      .to_return(status: 200, body: '{"ok":true}')

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/old",
      payload: "{}",
      headers: {}
    )

    assert result.success?
    assert_equal "https://example.com/new", result.final_url
  end

  test "post follows 302 redirect" do
    stub_request(:post, "https://example.com/temp")
      .to_return(status: 302, headers: { "Location" => "https://example.com/dest" })

    stub_request(:post, "https://example.com/dest")
      .to_return(status: 200, body: '{"ok":true}')

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/temp",
      payload: "{}",
      headers: {}
    )

    assert result.success?
    assert_equal "https://example.com/dest", result.final_url
  end

  test "post follows up to 5 redirects" do
    (1..5).each do |i|
      stub_request(:post, "https://example.com/r#{i}")
        .to_return(status: 302, headers: { "Location" => "https://example.com/r#{i + 1}" })
    end

    stub_request(:post, "https://example.com/r6")
      .to_return(status: 200, body: '{"ok":true}')

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/r1",
      payload: "{}",
      headers: {}
    )

    assert result.success?
    assert_equal "https://example.com/r6", result.final_url
  end

  test "post fails after too many redirects" do
    (1..6).each do |i|
      stub_request(:post, "https://example.com/r#{i}")
        .to_return(status: 302, headers: { "Location" => "https://example.com/r#{i + 1}" })
    end

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/r1",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal "too_many_redirects", result.error_code
  end

  test "post rejects HTTPS to HTTP downgrade" do
    stub_request(:post, "https://example.com/secure")
      .to_return(status: 302, headers: { "Location" => "http://example.com/insecure" })

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "https://example.com/secure",
      payload: "{}",
      headers: {}
    )

    assert result.failure?
    assert_equal "insecure_redirect", result.error_code
    assert_match(/HTTPS.*HTTP/i, result.error_message)
  end

  test "post allows HTTP to HTTPS upgrade" do
    stub_request(:post, "http://example.com/old")
      .to_return(status: 302, headers: { "Location" => "https://example.com/new" })

    stub_request(:post, "https://example.com/new")
      .to_return(status: 200, body: '{"ok":true}')

    client = RedmineWebhookPlugin::Webhook::HttpClient.new
    result = client.post(
      url: "http://example.com/old",
      payload: "{}",
      headers: {}
    )

    assert result.success?
    assert_equal "https://example.com/new", result.final_url
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```


Expected: FAIL - redirect following not implemented

**Step 3: Add redirect following**

```ruby
# app/services/webhook/http_client.rb - replace the class
require "net/http"
require "uri"
require "openssl"

module RedmineWebhookPlugin::Webhook
  class HttpClient
    DEFAULT_TIMEOUT = 30
    DEFAULT_SSL_VERIFY = true
    MAX_REDIRECTS = 5

    class TooManyRedirectsError < StandardError; end
    class InsecureRedirectError < StandardError; end

    attr_reader :timeout, :ssl_verify

    def initialize(timeout: DEFAULT_TIMEOUT, ssl_verify: DEFAULT_SSL_VERIFY)
      @timeout = timeout
      @ssl_verify = ssl_verify
    end

    def post(url:, payload:, headers:)
      uri = URI.parse(url)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      redirect_count = 0
      original_scheme = uri.scheme

      loop do
        response = execute_request(uri, payload, headers)
        duration_ms = calculate_duration(start_time)

        if redirect?(response)
          redirect_count += 1

          if redirect_count > MAX_REDIRECTS
            return DeliveryResult.failure(
              error_code: "too_many_redirects",
              error_message: "Exceeded maximum of #{MAX_REDIRECTS} redirects",
              duration_ms: duration_ms
            )
          end

          new_uri = resolve_redirect(uri, response["Location"])

          if insecure_downgrade?(original_scheme, new_uri.scheme)
            return DeliveryResult.failure(
              error_code: "insecure_redirect",
              error_message: "Refusing to redirect from HTTPS to HTTP",
              duration_ms: duration_ms
            )
          end

          uri = new_uri
        else
          return build_result(response, duration_ms, uri.to_s)
        end
      end
    rescue TooManyRedirectsError => e
      duration_ms = calculate_duration(start_time)
      DeliveryResult.failure(
        error_code: "too_many_redirects",
        error_message: e.message,
        duration_ms: duration_ms
      )
    rescue InsecureRedirectError => e
      duration_ms = calculate_duration(start_time)
      DeliveryResult.failure(
        error_code: "insecure_redirect",
        error_message: e.message,
        duration_ms: duration_ms
      )
    rescue StandardError => e
      duration_ms = calculate_duration(start_time)
      build_error_result(e, duration_ms)
    end

    private

    def execute_request(uri, payload, headers)
      http = build_http(uri)
      request = build_post_request(uri, payload, headers)

      http.request(request)
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      if http.use_ssl?
        http.verify_mode = ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      end

      http
    end

    def build_post_request(uri, payload, headers)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = payload
      headers.each { |key, value| request[key] = value }
      request
    end

    def redirect?(response)
      [301, 302, 303, 307, 308].include?(response.code.to_i) && response["Location"]
    end

    def resolve_redirect(original_uri, location)
      URI.join(original_uri, location)
    end

    def insecure_downgrade?(original_scheme, new_scheme)
      original_scheme == "https" && new_scheme == "http"
    end

    def calculate_duration(start_time)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    end

    def build_result(response, duration_ms, url)
      status = response.code.to_i
      error_code = ErrorClassifier.classify_http_status(status)

      if error_code
        DeliveryResult.failure(
          error_code: error_code,
          http_status: status,
          response_body: response.body,
          duration_ms: duration_ms
        )
      else
        DeliveryResult.success(
          http_status: status,
          response_body: response.body,
          duration_ms: duration_ms,
          final_url: url
        )
      end
    end

    def build_error_result(exception, duration_ms)
      DeliveryResult.failure(
        error_code: ErrorClassifier.classify(exception),
        error_message: exception.message,
        duration_ms: duration_ms
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/http_client_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 18 tests, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/http_client.rb test/unit/webhook/http_client_test.rb
git commit -m "feat(d): add HttpClient redirect following with security checks"
```

---

## Task 13: Run All Workstream D Tests

**Step 1: Run full test suite for Workstream D**

Run:
```bash
# Primary version
VERSION=5.1.0 tools/test/run-test.sh

# Also verify on other versions
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
```


Expected: All tests pass (existing + new delivery infrastructure tests)

**Step 2: Verify services in Rails console**

Run: `cd /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.1 && bundle exec rails console -e test`

```ruby
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

**Step 3: Commit final Workstream D**

```bash
git add -A
git commit -m "feat(d): complete delivery infrastructure - HTTP client, retry policy, API key resolver"
```

---

## Acceptance Criteria Checklist

- [ ] DeliveryResult value object with success/failure factories
- [ ] ErrorClassifier maps exceptions to error codes
- [ ] RetryPolicy calculates exponential backoff with jitter
- [ ] RetryPolicy determines if error is retryable
- [ ] ApiKeyResolver finds user's API token
- [ ] ApiKeyResolver auto-generates token when missing (if REST API enabled)
- [ ] ApiKeyResolver fingerprints API keys with SHA256
- [ ] HeadersBuilder constructs standard webhook headers
- [ ] HttpClient makes HTTP POST with configurable timeout
- [ ] HttpClient follows up to 5 redirects
- [ ] HttpClient rejects HTTPS to HTTP downgrade
- [ ] HttpClient classifies all network/SSL errors
- [ ] All unit tests pass