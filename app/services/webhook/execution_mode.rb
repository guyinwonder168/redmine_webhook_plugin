module RedmineWebhookPlugin
  module Webhook
    class ExecutionMode
      INLINE_ADAPTER_MATCH = /Inline/.freeze

      def self.detect
        override = _override_setting
        return override if override

        adapter = _queue_adapter
        return :activejob if adapter && !_inline_adapter?(adapter)

        :db_runner
      end

      def self._override_setting
        return nil unless Setting.respond_to?(:plugin_redmine_webhook_plugin)

        settings = Setting.plugin_redmine_webhook_plugin
        value = settings.is_a?(Hash) ? settings["execution_mode"] : nil
        return nil if value.blank? || value == "auto"

        value.to_sym
      rescue StandardError
        nil
      end
      private_class_method :_override_setting

      def self._queue_adapter
        ActiveJob::Base.queue_adapter
      rescue StandardError
        nil
      end
      private_class_method :_queue_adapter

      def self._inline_adapter?(adapter)
        adapter.class.name.to_s.match?(INLINE_ADAPTER_MATCH)
      end
      private_class_method :_inline_adapter?
    end
  end
end
