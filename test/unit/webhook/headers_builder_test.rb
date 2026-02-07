require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::HeadersBuilderTest < ActiveSupport::TestCase
  test "build returns base headers without optional values" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-1",
      event_type: "issue",
      action: "created",
      api_key: nil,
      delivery_id: nil,
      custom_headers: {}
    )

    expected = {
      "Content-Type" => "application/json; charset=utf-8",
      "User-Agent" => expected_user_agent,
      "X-Redmine-Event-ID" => "event-1",
      "X-Redmine-Event" => "issue.created"
    }

    assert_equal expected, headers
  end

  test "build sets user agent with plugin and Redmine version" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-2",
      event_type: "issue",
      action: "updated",
      api_key: nil,
      delivery_id: nil,
      custom_headers: {}
    )

    assert_equal expected_user_agent, headers["User-Agent"]
  end

  test "build sets event header from event type and action" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-3",
      event_type: "time_entry",
      action: "deleted",
      api_key: nil,
      delivery_id: nil,
      custom_headers: {}
    )

    assert_equal "time_entry.deleted", headers["X-Redmine-Event"]
  end

  test "build includes api key when provided" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-4",
      event_type: "issue",
      action: "created",
      api_key: "token",
      delivery_id: nil,
      custom_headers: {}
    )

    assert_equal "token", headers["X-Redmine-API-Key"]
  end

  test "build excludes api key when missing" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-5",
      event_type: "issue",
      action: "created",
      api_key: nil,
      delivery_id: nil,
      custom_headers: {}
    )

    assert_nil headers["X-Redmine-API-Key"]
  end

  test "build includes delivery id when provided" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-6",
      event_type: "issue",
      action: "created",
      api_key: nil,
      delivery_id: 42,
      custom_headers: {}
    )

    assert_equal "42", headers["X-Redmine-Delivery"]
  end

  test "build excludes delivery id when missing" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-7",
      event_type: "issue",
      action: "created",
      api_key: nil,
      delivery_id: nil,
      custom_headers: {}
    )

    assert_nil headers["X-Redmine-Delivery"]
  end

  test "build merges custom headers" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-8",
      event_type: "issue",
      action: "created",
      api_key: nil,
      delivery_id: nil,
      custom_headers: { "X-Custom" => "value" }
    )

    assert_equal "value", headers["X-Custom"]
  end

  test "build allows custom headers to override standard headers" do
    headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
      event_id: "event-9",
      event_type: "issue",
      action: "created",
      api_key: nil,
      delivery_id: nil,
      custom_headers: { "Content-Type" => "application/xml" }
    )

    assert_equal "application/xml", headers["Content-Type"]
  end

  private

  def expected_user_agent
    plugin_version = Redmine::Plugin.find(:redmine_webhook_plugin).version.to_s
    redmine_version = Redmine::VERSION.to_s

    "RedmineWebhook/#{plugin_version} (Redmine/#{redmine_version})"
  end
end
