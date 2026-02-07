require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DispatcherTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :issues, :issue_categories, :enumerations, :time_entries, :journals

  setup do
    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all
  end

  test "Dispatcher class exists under RedmineWebhookPlugin::Webhook namespace" do
    assert defined?(RedmineWebhookPlugin::Webhook::Dispatcher), "RedmineWebhookPlugin::Webhook::Dispatcher should be defined"
  end

  test "Dispatcher responds to dispatch method" do
    assert_respond_to RedmineWebhookPlugin::Webhook::Dispatcher, :dispatch
  end

  test "dispatch returns empty array" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1)
    }

    result = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)
    assert_kind_of Array, result
    assert_empty result
  end

  test "dispatch filters endpoints by enabled flag and matches_event?" do
    # Create test endpoints
    enabled_matching = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Enabled Matching",
      url: "https://example.com/hook1",
      enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1]
    )
    enabled_non_matching = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Enabled Non-Matching",
      url: "https://example.com/hook2",
      enabled: true,
      events_config: { "issue" => { "updated" => true } },
      project_ids: []
    )
    disabled_matching = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Disabled Matching",
      url: "https://example.com/hook3",
      enabled: false,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1]
    )

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      project_id: 1,
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1),
      project: Project.find(1)
    }

    result = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    # Should create delivery only for enabled matching endpoint
    assert_equal 1, result.length
    assert_kind_of RedmineWebhookPlugin::Webhook::Delivery, result.first
    assert_equal enabled_matching.id, result.first.endpoint_id
  end

  test "dispatch creates delivery records for each matched endpoint" do
    # Create two enabled matching endpoints
    endpoint1 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint 1",
      url: "https://example.com/hook1",
      enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1],
      retry_config: { "max_attempts" => 3, "base_delay" => 30 }
    )
    endpoint2 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint 2",
      url: "https://example.com/hook2",
      enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1],
      retry_config: { "max_attempts" => 5, "base_delay" => 60 }
    )

    event_id = SecureRandom.uuid
    event_data = {
      event_id: event_id,
      event_type: "issue",
      action: "created",
      project_id: 1,
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1),
      project: Project.find(1)
    }

    # Dispatch the event
    deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    # Verify two delivery records were created
    assert_equal 2, deliveries.length, "Should create one delivery per matched endpoint"

    # Verify all deliveries are Delivery instances
    deliveries.each do |delivery|
      assert_kind_of RedmineWebhookPlugin::Webhook::Delivery, delivery
    end

    # Verify delivery for endpoint1
    delivery1 = deliveries.find { |d| d.endpoint_id == endpoint1.id }
    assert_not_nil delivery1, "Should have delivery for endpoint1"
    assert_equal event_id, delivery1.event_id
    assert_equal "issue", delivery1.event_type
    assert_equal "created", delivery1.action
    assert_equal "pending", delivery1.status
    assert_equal endpoint1.id, delivery1.endpoint_id
    assert_equal endpoint1.webhook_user_id, delivery1.webhook_user_id

    # Verify payload was built
    assert_kind_of Hash, JSON.parse(delivery1.payload)
    parsed_payload = JSON.parse(delivery1.payload)
    assert_equal event_id, parsed_payload["event_id"]
    assert_equal "issue", parsed_payload["event_type"]
    assert_equal "created", parsed_payload["action"]

    # Verify retry policy snapshot from endpoint config
    assert_kind_of Hash, JSON.parse(delivery1.retry_policy_snapshot)
    parsed_retry = JSON.parse(delivery1.retry_policy_snapshot)
    assert_equal 3, parsed_retry["max_attempts"]
    assert_equal 30, parsed_retry["base_delay"]

    # Verify delivery for endpoint2
    delivery2 = deliveries.find { |d| d.endpoint_id == endpoint2.id }
    assert_not_nil delivery2, "Should have delivery for endpoint2"
    assert_equal event_id, delivery2.event_id
    assert_equal endpoint2.id, delivery2.endpoint_id

    # Verify endpoint2 has different retry policy
    parsed_retry2 = JSON.parse(delivery2.retry_policy_snapshot)
    assert_equal 5, parsed_retry2["max_attempts"]
    assert_equal 60, parsed_retry2["base_delay"]
  end

  test "dispatch enqueues DeliveryJob when execution mode is activejob" do
    RedmineWebhookPlugin::Webhook::ExecutionMode.stubs(:detect).returns(:activejob)

    RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint ActiveJob",
      url: "https://example.com/hook",
      enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1]
    )

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      project_id: 1,
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1)
    }

    # Expect DeliveryJob.perform_later to be called
    RedmineWebhookPlugin::Webhook::DeliveryJob.expects(:perform_later).once

    RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)
  end

  test "dispatch does not enqueue DeliveryJob when execution mode is db_runner" do
    RedmineWebhookPlugin::Webhook::ExecutionMode.stubs(:detect).returns(:db_runner)

    RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint DB Runner",
      url: "https://example.com/hook",
      enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1]
    )

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      project_id: 1,
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1)
    }

    # Expect DeliveryJob.perform_later NOT to be called
    RedmineWebhookPlugin::Webhook::DeliveryJob.expects(:perform_later).never

    RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)
  end
end
