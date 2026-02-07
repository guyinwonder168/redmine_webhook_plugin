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

  test "validates event_id presence" do
    delivery = RedmineWebhookPlugin::Webhook::Delivery.new(event_id: nil, event_type: "issue", action: "created")
    assert_not delivery.valid?
    assert delivery.errors[:event_id].present?
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
    assert_nil delivery.locked_by
    assert_nil delivery.locked_at
  end
end
