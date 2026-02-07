require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DeliveryResultTest < ActiveSupport::TestCase
  test "success factory builds successful result" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(
      http_status: 200,
      response_body: "OK",
      duration_ms: 120,
      final_url: "https://example.test/hook"
    )

    assert result.success?
    assert_equal 200, result.http_status
    assert_equal "OK", result.response_body
    assert_equal 120, result.duration_ms
    assert_equal "https://example.test/hook", result.final_url
    assert_nil result.error_code
    assert_nil result.error_message
  end

  test "failure factory builds failed result" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.failure(
      error_code: "connection_timeout",
      error_message: "Connection timed out",
      duration_ms: 250
    )

    assert_not result.success?
    assert_equal "connection_timeout", result.error_code
    assert_equal "Connection timed out", result.error_message
    assert_equal 250, result.duration_ms
    assert_nil result.http_status
  end

  test "response_body is truncated to 2kb" do
    long_body = "a" * 3000

    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(http_status: 200, response_body: long_body)

    assert_equal 2048, result.response_body.length
    assert_equal long_body[0, 2048], result.response_body
  end

  test "response_body can be nil" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(http_status: 204, response_body: nil)

    assert_nil result.response_body
  end

  test "response_body truncation preserves non-string values" do
    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(http_status: 200, response_body: 123)

    assert_equal 123, result.response_body
  end
end
