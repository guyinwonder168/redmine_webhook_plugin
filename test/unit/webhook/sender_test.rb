require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::SenderTest < ActiveSupport::TestCase
  test "Sender responds to send" do
    assert_respond_to RedmineWebhookPlugin::Webhook::Sender, :send
  end

  test "send marks delivering then success" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Primary",
      url: "https://example.test/webhooks",
      enabled: true,
      timeout: 12,
      ssl_verify: false
    )
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: "{\"hello\":\"world\"}"
    )

    headers = { "Content-Type" => "application/json" }
    RedmineWebhookPlugin::Webhook::HeadersBuilder.expects(:build).with(
      event_id: delivery.event_id,
      event_type: delivery.event_type,
      action: delivery.action,
      api_key: nil,
      delivery_id: delivery.id,
      custom_headers: {}
    ).returns(headers)

    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(
      http_status: 200,
      response_body: "OK",
      duration_ms: 125,
      final_url: endpoint.url
    )

    client = mock("http_client")
    client.expects(:post).with(
      url: endpoint.url,
      payload: delivery.payload,
      headers: headers
    ).returns(result)

    RedmineWebhookPlugin::Webhook::HttpClient.expects(:new).with(
      timeout: endpoint.timeout,
      ssl_verify: endpoint.ssl_verify
    ).returns(client)

    RedmineWebhookPlugin::Webhook::Sender.send(delivery)

    delivery.reload
    assert_equal "success", delivery.status
    assert_equal 200, delivery.http_status
    assert_equal "OK", delivery.response_body_excerpt
    assert_equal 125, delivery.duration_ms
    assert_not_nil delivery.delivered_at
  end

  test "send schedules retry when retryable failure occurs" do
    retry_config = {
      "max_attempts" => 5,
      "base_delay" => 60,
      "max_delay" => 3600,
      "retryable_statuses" => [408, 429, 500, 502, 503, 504]
    }
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Retry Endpoint",
      url: "https://example.test/webhooks",
      enabled: true,
      timeout: 12,
      ssl_verify: false,
      retry_config: retry_config
    )
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: "{\"hello\":\"world\"}",
      attempt_count: 0,
      retry_policy_snapshot: retry_config.to_json
    )

    headers = { "Content-Type" => "application/json" }
    RedmineWebhookPlugin::Webhook::HeadersBuilder.expects(:build).with(
      event_id: delivery.event_id,
      event_type: delivery.event_type,
      action: delivery.action,
      api_key: nil,
      delivery_id: delivery.id,
      custom_headers: {}
    ).returns(headers)

    result = RedmineWebhookPlugin::Webhook::DeliveryResult.failure(
      http_status: 503,
      response_body: "Service Unavailable",
      error_code: "server_error",
      duration_ms: 200,
      final_url: endpoint.url
    )

    client = mock("http_client")
    client.expects(:post).with(
      url: endpoint.url,
      payload: delivery.payload,
      headers: headers
    ).returns(result)

    RedmineWebhookPlugin::Webhook::HttpClient.expects(:new).with(
      timeout: endpoint.timeout,
      ssl_verify: endpoint.ssl_verify
    ).returns(client)

    initial_time = Time.current
    RedmineWebhookPlugin::Webhook::Sender.send(delivery)

    delivery.reload
    assert_equal "pending", delivery.status
    assert_equal 503, delivery.http_status
    assert_equal "Service Unavailable", delivery.response_body_excerpt
    assert_equal 200, delivery.duration_ms
    assert_equal 1, delivery.attempt_count
    assert_not_nil delivery.scheduled_at
    assert delivery.scheduled_at >= initial_time
  end

  test "send includes API key when endpoint has valid webhook_user" do
    webhook_user = User.find_by(id: 1)
    skip "User fixture not available" unless webhook_user

    api_key = "test-api-key-12345"

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Authenticated Endpoint",
      url: "https://example.test/webhooks",
      enabled: true,
      timeout: 12,
      ssl_verify: false,
      webhook_user: webhook_user
    )

    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      webhook_user_id: webhook_user.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: "{\"hello\":\"world\"}"
    )

    headers = { "Content-Type" => "application/json" }

    RedmineWebhookPlugin::Webhook::ApiKeyResolver.expects(:resolve).with(
      webhook_user
    ).returns(api_key)

    RedmineWebhookPlugin::Webhook::HeadersBuilder.expects(:build).with(
      event_id: delivery.event_id,
      event_type: delivery.event_type,
      action: delivery.action,
      api_key: api_key,
      delivery_id: delivery.id,
      custom_headers: {}
    ).returns(headers)

    result = RedmineWebhookPlugin::Webhook::DeliveryResult.success(
      http_status: 200,
      response_body: "OK",
      duration_ms: 125,
      final_url: endpoint.url
    )

    client = mock("http_client")
    client.expects(:post).with(
      url: endpoint.url,
      payload: delivery.payload,
      headers: headers
    ).returns(result)

    RedmineWebhookPlugin::Webhook::HttpClient.expects(:new).with(
      timeout: endpoint.timeout,
      ssl_verify: endpoint.ssl_verify
    ).returns(client)

    RedmineWebhookPlugin::Webhook::Sender.send(delivery)

    delivery.reload
    assert_equal "success", delivery.status
    assert_equal 200, delivery.http_status
    assert_equal "OK", delivery.response_body_excerpt
    assert_equal 125, delivery.duration_ms
    assert_not_nil delivery.delivered_at
  end

  test "send skips delivery when webhook_user is inactive" do
    webhook_user = User.create!(
      login: "inactive_user",
      firstname: "Inactive",
      lastname: "User",
      mail: "inactive@example.com",
      status: User::STATUS_ACTIVE
    )

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Inactive User Endpoint",
      url: "https://example.test/webhooks",
      enabled: true,
      timeout: 12,
      ssl_verify: false,
      webhook_user: webhook_user
    )

    # Make user inactive after endpoint is created (bypass validation)
    webhook_user.update!(status: User::STATUS_LOCKED)

    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      webhook_user_id: webhook_user.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: "{\"hello\":\"world\"}"
    )

    RedmineWebhookPlugin::Webhook::Sender.send(delivery)

    delivery.reload
    assert_equal "failed", delivery.status
    assert_equal "user_inactive", delivery.error_code
    assert_match /webhook user is not active/i, delivery.response_body_excerpt
  end
end
