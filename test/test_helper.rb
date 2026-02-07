require File.expand_path("../../../test/test_helper", __dir__)
require_relative "../app/services/webhook/payload_builder"
require_relative "../app/services/webhook/delivery_result"
require_relative "../app/services/webhook/error_classifier"
require_relative "../app/services/webhook/retry_policy"
require_relative "../app/services/webhook/api_key_resolver"
require_relative "../app/services/webhook/headers_builder"
require_relative "../app/services/webhook/http_client"
require_relative "../app/services/webhook/dispatcher"
require_relative "../app/services/webhook/execution_mode"
require_relative "../app/services/webhook/sender"
require_relative "../app/jobs/webhook/delivery_job"
require_relative "../app/models/redmine_webhook_plugin/webhook/endpoint"
require_relative "../app/models/redmine_webhook_plugin/webhook/delivery"

def IssuePriority.generate!(attributes={})
  @generated_priority_name ||= +'Priority 0'
  @generated_priority_name.succ!
  priority = IssuePriority.new(attributes)
  priority.name = @generated_priority_name.dup if priority.name.blank?
  priority.position ||= IssuePriority.maximum(:position).to_i + 1
  priority.active = true unless attributes.key?(:active)
  yield priority if block_given?
  priority.save!
  priority
end

# Test capture helper for unit test isolation
# Enables tests to verify event_data without checking Delivery records
# This is only for Workstream B tests that verify event capture, not delivery
module RedmineWebhookPlugin
  module Webhook
    module TestHelper
      class << self
        attr_accessor :last_event
      end

      # Enable event capture for tests
      def self.enable_capture!
        RedmineWebhookPlugin::Webhook::Dispatcher.test_capture_enabled = true
        @last_event = nil
      end

      # Disable event capture and return captured event
      def self.disable_capture
        RedmineWebhookPlugin::Webhook::Dispatcher.test_capture_enabled = false
        event = RedmineWebhookPlugin::Webhook::Dispatcher.test_last_event
        RedmineWebhookPlugin::Webhook::Dispatcher.test_last_event = nil
        @last_event = event
        event
      end

      # Convenience method: capture events in a block
      def self.capture_events
        enable_capture!
        yield
        disable_capture
      end
    end
  end
end
