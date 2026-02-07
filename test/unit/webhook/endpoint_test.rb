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

  test "validates name presence" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: nil, url: "https://example.com")
    assert_not endpoint.valid?
    assert endpoint.errors[:name].present?
  end

  test "validates name uniqueness" do
    RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")
    duplicate = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://other.com")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].present?
  end

  test "validates url presence" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: nil)
    assert_not endpoint.valid?
    assert endpoint.errors[:url].present?
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

  test "validates webhook_user_id must be active" do
    inactive = User.create!(
      login: "inactive",
      firstname: "Inactive",
      lastname: "User",
      mail: "inactive@example.com",
      status: User::STATUS_LOCKED
    )

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com", webhook_user_id: inactive.id)

    assert_not endpoint.valid?
    assert_includes endpoint.errors[:webhook_user_id], "must be an active user"
  end
end
