require File.expand_path("../test_helper", __dir__)

class WebhookDeliveryMigrationTest < ActiveSupport::TestCase
  test "webhook_deliveries table exists with required columns" do
    assert ActiveRecord::Base.connection.table_exists?(:webhook_deliveries),
           "webhook_deliveries table should exist"

    columns = ActiveRecord::Base.connection.columns(:webhook_deliveries).map(&:name)

    assert_includes columns, "endpoint_id"
    assert_includes columns, "webhook_user_id"
    assert_includes columns, "event_id"
    assert_includes columns, "event_type"
    assert_includes columns, "action"
    assert_includes columns, "resource_type"
    assert_includes columns, "resource_id"
    assert_includes columns, "sequence_number"
    assert_includes columns, "payload"
    assert_includes columns, "endpoint_url"
    assert_includes columns, "retry_policy_snapshot"
    assert_includes columns, "status"
    assert_includes columns, "attempt_count"
    assert_includes columns, "http_status"
    assert_includes columns, "error_code"
    assert_includes columns, "scheduled_at"
    assert_includes columns, "delivered_at"
    assert_includes columns, "duration_ms"
    assert_includes columns, "locked_at"
    assert_includes columns, "locked_by"
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