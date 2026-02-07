require "active_support/concern"
require_relative "../webhook_cleanup"

module RedmineWebhookPlugin
  module Patches
    module WebhookLifecyclePatch
      extend ActiveSupport::Concern
      include WebhookCleanup

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = resolve_actor
        if instance_variable_defined?(:@current_journal)
          @webhook_journal = instance_variable_get(:@current_journal)
        end
        Thread.current[:redmine_webhook_user] = User.current
      end

      def webhook_after_create
        return if @webhook_skip

        @webhook_changes ||= saved_changes
        @webhook_actor ||= resolve_actor

        begin
          RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
        rescue StandardError => e
          Rails.logger.error "[RedmineWebhookPlugin] Failed to dispatch create event: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      def webhook_after_update
        return if @webhook_skip

        @webhook_changes ||= saved_changes
        @webhook_actor ||= resolve_actor

        begin
          RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
        rescue StandardError => e
          Rails.logger.error "[RedmineWebhookPlugin] Failed to dispatch update event: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.transform_keys(&:to_sym)
        Thread.current[:redmine_webhook_user] = User.current
        @webhook_actor = resolve_actor
      end

      def webhook_after_destroy
        return if @webhook_skip

        snapshot = @webhook_snapshot || attributes.transform_keys(&:to_sym)
        @webhook_actor ||= resolve_actor

        begin
          event_data = webhook_event_data("deleted", nil, snapshot)
          event_data[:resource_snapshot] = snapshot
          RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)
        rescue StandardError => e
          Rails.logger.error "[RedmineWebhookPlugin] Failed to dispatch delete event: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      def webhook_event_data(action, changes, source)
        data = {
          event_type: webhook_event_type,
          action: action,
          resource: source,
          resource_ref: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: generate_event_id,
          sequence_number: generate_sequence_number
        }
        data[:journal] = @webhook_journal if action == "updated" && @webhook_journal
        data
      ensure
        cleanup_webhook_state
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          {
            type: webhook_event_type,
            id: source[:id] || source["id"],
            project_id: source[:project_id] || source["project_id"],
            issue_id: source[:issue_id] || source["issue_id"]
          }.compact
        else
          hash = { type: webhook_event_type, id: source.id }
          hash[:project_id] = source.project_id if source.respond_to?(:project_id)
          hash[:issue_id] = source.issue_id if source.respond_to?(:issue_id)
          hash
        end
      end
    end
  end
end
