require File.expand_path("../test_helper", __dir__)

class LocalizationTest < ActiveSupport::TestCase
  test "webhook locale keys exist" do
    assert_equal "Webhook Endpoints", I18n.t(:label_webhook_endpoints)
    assert_equal "New Endpoint", I18n.t(:label_webhook_endpoint_new)
    assert_equal "Edit Endpoint", I18n.t(:label_webhook_endpoint_edit)
    assert_equal "Payload Mode", I18n.t(:field_payload_mode)
    assert_equal "Retry Policy", I18n.t(:label_webhook_retry)
    assert_equal "Issues", I18n.t(:label_issue_plural)
    assert_equal "Time Entries", I18n.t(:label_time_entry_plural)
    assert_equal "Timeout (seconds)", I18n.t(:field_timeout)
  end

  test "settings locale keys exist" do
    assert_equal "Execution Mode", I18n.t(:label_execution_mode)
    assert_equal "Auto-detect", I18n.t(:label_execution_mode_auto)
    assert_equal "ActiveJob", I18n.t(:label_execution_mode_activejob)
    assert_equal "Database Runner", I18n.t(:label_execution_mode_db_runner)
    assert_equal "Retention Days (Success)", I18n.t(:label_retention_success_days)
    assert_equal "Retention Days (Failed)", I18n.t(:label_retention_failed_days)
    assert_equal "Pause Deliveries", I18n.t(:label_deliveries_paused)
  end

  test "delivery log locale keys exist" do
    assert_equal "Event ID", I18n.t(:label_event_id)
    assert_equal "Payload", I18n.t(:label_payload)
    assert_equal "API Key Fingerprint", I18n.t(:label_api_key_fingerprint)
    assert_equal "Response Excerpt", I18n.t(:label_response_excerpt)
    assert_equal "Replay Delivery", I18n.t(:button_replay_delivery)
    assert_equal "Replay Selected", I18n.t(:button_replay_selected)
    assert_equal "CSV", I18n.t(:label_export_options)
  end

  test "delivery status locale keys exist" do
    assert_equal "Pending", I18n.t(:label_status_pending)
    assert_equal "Delivering", I18n.t(:label_status_delivering)
    assert_equal "Success", I18n.t(:label_status_success)
    assert_equal "Failed", I18n.t(:label_status_failed)
    assert_equal "Dead", I18n.t(:label_status_dead)
    assert_equal "Endpoint Deleted", I18n.t(:label_status_endpoint_deleted)
  end

  test "delivery detail locale keys exist" do
    assert_equal "Event Details", I18n.t(:label_delivery_details_event)
    assert_equal "Delivery Status", I18n.t(:label_delivery_details_status)
    assert_equal "Duration", I18n.t(:label_duration)
    assert_equal "Attempts", I18n.t(:label_attempts)
    assert_equal "Error Code", I18n.t(:label_error_code)
    assert_equal "Is Test", I18n.t(:label_is_test)
    assert_equal "Created", I18n.t(:label_created_at_full)
    assert_equal "Scheduled", I18n.t(:label_scheduled_at)
    assert_equal "Delivered", I18n.t(:label_delivered_at)
    assert_equal "Updated", I18n.t(:label_updated_at_full)
    assert_equal "Response Body", I18n.t(:label_response_body)
    assert_equal "Webhook Payload", I18n.t(:label_webhook_payload)
    assert_equal "Toggle payload", I18n.t(:label_toggle_payload)
  end

  test "notice locale keys exist" do
    assert_equal "Delivery has been queued for replay", I18n.t(:notice_webhook_delivery_replayed)
    assert_equal "5 deliveries queued for replay", I18n.t(:notice_webhook_bulk_replay, count: 5)
    assert_equal "Test delivery queued", I18n.t(:notice_webhook_test_queued)
  end
end
