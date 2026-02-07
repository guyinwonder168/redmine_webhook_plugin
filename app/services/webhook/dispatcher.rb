module RedmineWebhookPlugin
  module Webhook
    class Dispatcher
      # Test capture mechanism for unit test isolation
      # Allows tests to verify event_data without checking Delivery records
      # Only active when TestStub module is loaded
      class << self
        attr_accessor :test_capture_enabled, :test_last_event
      end
      @test_capture_enabled = false
      @test_last_event = nil

      # Accepts event data and creates delivery records for matching endpoints.
      # Returns an array of created delivery records.
      #
      # @param event_data [Hash] Event data containing event_id, event_type, action, etc.
      # @return [Array<Delivery>] Array of delivery records
      def self.dispatch(event_data)
        # Capture for test isolation (only when enabled)
        @test_last_event = event_data if @test_capture_enabled

        return [] if deliveries_paused?

        event_type = event_data[:event_type]
        action = event_data[:action]
        project_id = event_data[:project_id]

        matched_endpoints = Endpoint.enabled.select do |endpoint|
          endpoint.matches_event?(event_type, action, project_id)
        end

        # Create delivery record for each matched endpoint
        deliveries = matched_endpoints.map do |endpoint|
          build_delivery(event_data, endpoint)
        end

        # Process deliveries based on execution mode
        if ExecutionMode.detect == :activejob
          deliveries.each do |delivery|
            DeliveryJob.perform_later(delivery.id)
          end
        end

        deliveries
      end

      def self.build_delivery(event_data, endpoint)
        payload_mode = endpoint.payload_mode || "minimal"

        # Build payload using PayloadBuilder
        payload_hash = PayloadBuilder.new(event_data, payload_mode).build

        # Create delivery record
        Delivery.create!(
          endpoint_id: endpoint.id,
          webhook_user_id: endpoint.webhook_user_id,
          event_id: event_data[:event_id],
          event_type: event_data[:event_type],
          action: event_data[:action],
          status: Delivery::PENDING,
          payload: payload_hash.to_json,
          retry_policy_snapshot: endpoint.retry_config.to_json
        )
      end

      def self.deliveries_paused?
        settings = Setting.plugin_redmine_webhook_plugin rescue {}
        settings.is_a?(Hash) && settings["deliveries_paused"] == "1"
      end
    end
  end
end
