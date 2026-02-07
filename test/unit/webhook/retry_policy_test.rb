require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::RetryPolicyTest < ActiveSupport::TestCase
  test "initializes with default values" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal 5, policy.max_attempts
    assert_equal 60, policy.base_delay
    assert_equal 3600, policy.max_delay
    assert_equal [408, 429, 500, 502, 503, 504], policy.retryable_statuses
  end

  test "initializes with custom config values" do
    custom_config = {
      "max_attempts" => 3,
      "base_delay" => 30,
      "max_delay" => 1800,
      "retryable_statuses" => [500, 503]
    }
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(custom_config)

    assert_equal 3, policy.max_attempts
    assert_equal 30, policy.base_delay
    assert_equal 1800, policy.max_delay
    assert_equal [500, 503], policy.retryable_statuses
  end

  test "normalizes symbol keys in config" do
    symbol_config = {
      max_attempts: 4,
      base_delay: 45,
      max_delay: 900,
      retryable_statuses: [429, 500]
    }
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(symbol_config)

    assert_equal 4, policy.max_attempts
    assert_equal 45, policy.base_delay
    assert_equal 900, policy.max_delay
    assert_equal [429, 500], policy.retryable_statuses
  end

  test "accepts mixed symbol and string keys" do
    mixed_config = {
      "max_attempts" => 2,
      :base_delay => 120,
      "max_delay" => 7200,
      :retryable_statuses => [408, 500, 502, 503, 504]
    }
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(mixed_config)

    assert_equal 2, policy.max_attempts
    assert_equal 120, policy.base_delay
    assert_equal 7200, policy.max_delay
    assert_equal [408, 500, 502, 503, 504], policy.retryable_statuses
  end

  test "retryable? returns true for retryable http status" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal true, policy.retryable?(http_status: 503, error_code: nil, ssl_verify: true)
  end

  test "retryable? returns true for retryable error code" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal true, policy.retryable?(http_status: nil, error_code: "connection_timeout", ssl_verify: true)
  end

  test "retryable? treats ssl_error as retryable when ssl verification is disabled" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal true, policy.retryable?(http_status: nil, error_code: "ssl_error", ssl_verify: false)
  end

  test "retryable? treats ssl_error as non-retryable when ssl verification is enabled" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal false, policy.retryable?(http_status: nil, error_code: "ssl_error", ssl_verify: true)
  end

  test "should_retry? returns false when attempts reach max_attempts" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("max_attempts" => 2)

    assert_equal false, policy.should_retry?(attempt_count: 2, http_status: 503, error_code: nil, ssl_verify: true)
  end

  test "should_retry? returns true when retryable and attempts remain" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("max_attempts" => 3)

    assert_equal true, policy.should_retry?(attempt_count: 1, http_status: 503, error_code: nil, ssl_verify: true)
  end

  test "next_delay returns base_delay for first attempt without jitter" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new

    assert_equal 60, policy.next_delay(attempt_number: 0, jitter: 1.0)
  end

  test "next_delay caps at max_delay when exponential exceeds limit" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("max_delay" => 100)

    assert_equal 100, policy.next_delay(attempt_number: 3, jitter: 1.0)
  end

  test "next_delay applies numeric jitter factor" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new("base_delay" => 100)

    assert_equal 110, policy.next_delay(attempt_number: 0, jitter: 1.1)
  end

  test "next_retry_at returns time shifted by next_delay" do
    policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new
    now = Time.utc(2025, 1, 1, 0, 0, 0)

    assert_equal now + 120, policy.next_retry_at(attempt_number: 1, now: now, jitter: 1.0)
  end
end
