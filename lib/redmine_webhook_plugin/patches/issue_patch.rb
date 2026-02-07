require "active_support/concern"
require_relative "../event_helpers"
require_relative "webhook_lifecycle_patch"

module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        include WebhookLifecyclePatch
        include RedmineWebhookPlugin::EventHelpers
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = resolve_actor

        Thread.current[:redmine_webhook_user] = User.current
        @webhook_journal = @current_journal
      end

      def webhook_after_create
        return if @webhook_skip

        begin
          RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
        rescue StandardError => e
          Rails.logger.error "[RedmineWebhookPlugin] Failed to dispatch create event: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      def webhook_after_update
        return if @webhook_skip

        begin
          RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
        rescue StandardError => e
          Rails.logger.error "[RedmineWebhookPlugin] Failed to dispatch update event: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = resolve_actor
      end

      def webhook_after_destroy
        return if @webhook_skip

        begin
          RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
        rescue StandardError => e
          Rails.logger.error "[RedmineWebhookPlugin] Failed to dispatch delete event: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      def webhook_event_data(action, changes, source)
        data = {
          event_type: "issue",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: generate_event_id,
          sequence_number: generate_sequence_number
        }
        data[:journal] = @webhook_journal if action == "updated" && @webhook_journal
        data
      end

      def webhook_event_type
        "issue"
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          {
            type: "issue",
            id: source["id"] || source[:id],
            project_id: source["project_id"] || source[:project_id]
          }
        else
          { type: "issue", id: source.id, project_id: source.project_id }
        end
      end
    end
  end
end
