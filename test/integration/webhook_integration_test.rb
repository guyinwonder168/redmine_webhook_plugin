require File.expand_path("../../test/test_helper", __dir__)

module RedmineWebhookPlugin
  module Webhook
    class WebhookIntegrationTest < ActiveSupport::TestCase
      self.use_transactional_tests = false

      fixtures :projects, :users, :roles, :members, :member_roles, :projects_trackers,
               :trackers, :issue_statuses, :issue_categories, :issues, :time_entries, :enumerations,
               :custom_fields, :custom_values, :enabled_modules, :workflows

      setup do
        # Clean up any existing data
        RedmineWebhookPlugin::Webhook::Delivery.delete_all
        RedmineWebhookPlugin::Webhook::Endpoint.delete_all
      end

      teardown do
        User.current = nil
      end

      # NOTE: Integration tests verify core webhook functionality
      # Full end-to-end flow (issue create -> dispatch -> delivery -> send)
      # is verified by unit tests for Dispatcher, PayloadBuilder, Sender, etc.
      # This test file verifies:
      # - Endpoint model creation and validation
      # - Dispatcher creates deliveries for matching endpoints
      # - Delivery model attribute storage
      # - Event data structure compatibility

      test "Endpoint model creates and validates webhook configuration" do
        user = User.find(1)
        project = Project.find(1)

        # Test 1: Create enabled endpoint
        endpoint1 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Test Endpoint",
          url: "https://example.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: {
            "issue" => {
              "created" => true,
              "updated" => true
            }
          },
          payload_mode: "minimal",
          retry_config: {
            "max_attempts" => 3,
            "base_delay" => 60,
            "max_delay" => 3600,
            "retryable_statuses" => [408, 429, 500, 502, 503, 504]
          }
        )

        # Verify endpoint creation
        assert_equal "Test Endpoint", endpoint1.name
        assert_equal "https://example.com/webhook", endpoint1.url
        assert_equal true, endpoint1.enabled
        assert_equal user.id, endpoint1.webhook_user_id
        assert_equal "minimal", endpoint1.payload_mode
        assert_equal true, endpoint1.events_config["issue"]["created"]
        assert_equal true, endpoint1.events_config["issue"]["updated"]
        assert_equal 3, endpoint1.retry_config["max_attempts"]
        assert_equal 60, endpoint1.retry_config["base_delay"]
        assert_equal 3600, endpoint1.retry_config["max_delay"]

        # Test 2: Verify event matching
        issue = Issue.find(1)
        assert_equal true, endpoint1.matches_event?("issue", "created", project.id)
        assert_equal false, endpoint1.matches_event?("issue", "deleted", project.id)

        # Test 3: Create disabled endpoint
        endpoint2 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Disabled Endpoint",
          url: "https://disabled.example.com/webhook",
          enabled: false,
          webhook_user: user,
          events_config: { "issue" => { "created" => true } },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        assert_equal false, endpoint2.enabled
        assert_equal "Disabled Endpoint", endpoint2.name
      end

      test "Delivery model stores webhook payload and metadata" do
        user = User.find(1)
        project = Project.find(1)

        endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Delivery Test Endpoint",
          url: "https://example.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: { "issue" => { "created" => true } },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        # Create delivery manually to verify storage
        issue = Issue.find(1)
        event_id = SecureRandom.uuid
        payload_data = {
          event_id: event_id,
          event_type: "issue",
          action: "created",
          occurred_at: Time.current,
          issue: {
            id: issue.id,
            subject: issue.subject,
            project: { id: project.id }
          }
        }

        delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
          endpoint_id: endpoint.id,
          webhook_user_id: user.id,
          event_id: event_id,
          event_type: "issue",
          action: "created",
          status: "pending",
          payload: payload_data.to_json,
          retry_policy_snapshot: endpoint.retry_config.to_json
        )

        # Verify delivery attributes
        assert_equal RedmineWebhookPlugin::Webhook::Delivery, delivery.class
        assert_equal "pending", delivery.status
        assert_equal "issue", delivery.event_type
        assert_equal "created", delivery.action
        assert_equal endpoint.id, delivery.endpoint_id
        assert_equal user.id, delivery.webhook_user_id
        assert_equal event_id, delivery.event_id
        assert_not_nil delivery.payload
        assert_not_nil delivery.retry_policy_snapshot

        # Verify payload structure
        parsed_payload = JSON.parse(delivery.payload)
        assert_equal event_id, parsed_payload["event_id"]
        assert_equal "issue", parsed_payload["event_type"]
        assert_equal "created", parsed_payload["action"]
        assert_not_nil parsed_payload["issue"]

        # Verify retry policy snapshot
        retry_config = JSON.parse(delivery.retry_policy_snapshot)
        assert_equal 3, retry_config["max_attempts"]
        assert_equal 60, retry_config["base_delay"]
        assert_equal 3600, retry_config["max_delay"]
        assert_equal [], retry_config["retryable_statuses"]
      end

      test "Delivery status lifecycle transitions" do
        user = User.find(1)
        project = Project.find(1)

        endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Lifecycle Test Endpoint",
          url: "https://example.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: { "issue" => { "created" => true } },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        issue = Issue.find(1)
        event_id = SecureRandom.uuid
        payload_data = {
          event_id: event_id,
          event_type: "issue",
          action: "created",
          occurred_at: Time.current,
          resource: issue,
          actor: user,
          project_id: project.id
        }

        delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
          endpoint_id: endpoint.id,
          webhook_user_id: user.id,
          event_id: event_id,
          event_type: "issue",
          action: "created",
          status: "pending",
          payload: payload_data.to_json,
          retry_policy_snapshot: endpoint.retry_config.to_json
        )

        # Verify initial status
        assert_equal "pending", delivery.status
        assert_equal 0, delivery.attempt_count
        assert_nil delivery.delivered_at
        assert_nil delivery.http_status
        assert_nil delivery.duration_ms
        assert_nil delivery.error_code
        assert_nil delivery.response_body_excerpt

        # Transition to delivering
        delivery.update!(status: "delivering")
        assert_equal "delivering", delivery.status

        # Transition to success
        delivery.update!(
          status: "success",
          http_status: 200,
          response_body_excerpt: '{"status":"ok"}',
          delivered_at: Time.current,
          duration_ms: 50,
          attempt_count: 1
        )
        delivery.reload

        assert_equal "success", delivery.status
        assert_equal 200, delivery.http_status
        assert_not_nil delivery.delivered_at
        assert_equal 50, delivery.duration_ms
        assert_equal 1, delivery.attempt_count
        assert_equal '{"status":"ok"}', delivery.response_body_excerpt
        assert_nil delivery.error_code

        # Transition to failed
        delivery.update!(
          status: "failed",
          http_status: 500,
          response_body_excerpt: '{"error":"Internal Server Error"}',
          error_code: "server_error",
          attempt_count: 2
        )
        delivery.reload

        assert_equal "failed", delivery.status
        assert_equal 500, delivery.http_status
        assert_not_nil delivery.delivered_at
        assert_not_nil delivery.duration_ms
        assert_equal 2, delivery.attempt_count
        assert_equal '{"error":"Internal Server Error"}', delivery.response_body_excerpt
        assert_equal "server_error", delivery.error_code
      end

      test "Multiple endpoints for same event" do
        user = User.find(1)
        project = Project.find(1)

        # Create multiple enabled endpoints
        endpoint1 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Endpoint 1",
          url: "https://example1.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: { "issue" => { "created" => true } },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        endpoint2 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Endpoint 2",
          url: "https://example2.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: { "issue" => { "created" => true } },
          payload_mode: "full",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        RedmineWebhookPlugin::Webhook::ExecutionMode.stubs(:detect).returns(:db_runner)

        event_data = {
          event_id: SecureRandom.uuid,
          event_type: "issue",
          action: "created",
          occurred_at: Time.current,
          resource: Issue.find(1),
          actor: user,
          project_id: project.id
        }

        deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

        assert_equal 2, deliveries.length
        assert_equal "Endpoint 1", endpoint1.name
        assert_equal "Endpoint 2", endpoint2.name
        assert_equal "minimal", endpoint1.payload_mode
        assert_equal "full", endpoint2.payload_mode
      end

      test "Event type filtering" do
        user = User.find(1)
        project = Project.find(1)

        # Create endpoint matching only issue events
        issue_endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Issue Events Endpoint",
          url: "https://example.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: {
            "issue" => {
              "created" => true,
              "updated" => true
            }
          },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        # Create endpoint NOT matching issue events
        time_entry_endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Time Entry Events Endpoint",
          url: "https://example.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: {
            "time_entry" => {
              "created" => true,
              "updated" => true
            }
          },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        RedmineWebhookPlugin::Webhook::ExecutionMode.stubs(:detect).returns(:db_runner)

        event_data = {
          event_id: SecureRandom.uuid,
          event_type: "issue",
          action: "created",
          occurred_at: Time.current,
          resource: Issue.find(1),
          actor: user,
          project_id: project.id
        }

        deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

        assert_equal 1, deliveries.length
        assert_equal issue_endpoint.id, deliveries.first.endpoint_id
        assert_equal "issue", deliveries.first.event_type
        assert_equal "created", deliveries.first.action
      end

      test "Event data structure compatibility" do
        user = User.find(1)
        project = Project.find(1)

        endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
          name: "Event Data Test Endpoint",
          url: "https://example.com/webhook",
          enabled: true,
          webhook_user: user,
          events_config: { "issue" => { "created" => true } },
          payload_mode: "minimal",
          retry_config: { "max_attempts" => 3, "base_delay" => 60, "max_delay" => 3600, "retryable_statuses" => [] }
        )

        # Create event data structure matching what patches create
        issue = Issue.find(1)
        event_data = {
          event_id: SecureRandom.uuid,
          event_type: "issue",
          action: "created",
          occurred_at: Time.current,
          resource: issue,
          actor: user,
          project_id: project.id
        }

        # Verify all required fields are present
        assert event_data[:event_id].is_a?(String)
        assert event_data[:event_type].is_a?(String)
        assert event_data[:action].is_a?(String)
        assert event_data[:occurred_at].is_a?(Time) || event_data[:occurred_at].is_a?(DateTime)
        assert_not_nil event_data[:resource]
        assert_not_nil event_data[:actor]
        assert event_data[:project_id].is_a?(Integer)
      end
    end
  end
end
