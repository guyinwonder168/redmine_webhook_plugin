module RedmineWebhookPlugin
  module Webhook
    class HeadersBuilder
      CONTENT_TYPE = "application/json; charset=utf-8".freeze
      API_HEADER = "X-Redmine-API-Key".freeze
      DELIVERY_HEADER = "X-Redmine-Delivery".freeze

      def self.build(event_id:, event_type:, action:, api_key:, delivery_id:, custom_headers: {})
        headers = {
          "Content-Type" => CONTENT_TYPE,
          "User-Agent" => user_agent,
          "X-Redmine-Event-ID" => event_id.to_s,
          "X-Redmine-Event" => "#{event_type}.#{action}"
        }

        headers = add_optional_header(headers, API_HEADER, api_key)
        headers = add_optional_header(headers, DELIVERY_HEADER, delivery_id)
        merge_custom_headers(headers, custom_headers)
      end

      def self.user_agent
        plugin_version = Redmine::Plugin.find(:redmine_webhook_plugin).version.to_s
        redmine_version = Redmine::VERSION.to_s

        "RedmineWebhook/#{plugin_version} (Redmine/#{redmine_version})"
      end

      def self.add_optional_header(headers, name, value)
        normalized = value.to_s
        return headers if normalized.empty?

        headers.merge(name => normalized)
      end

      def self.merge_custom_headers(headers, custom_headers)
        normalized = (custom_headers || {}).each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end

        headers.merge(normalized)
      end

      private_class_method :user_agent, :add_optional_header, :merge_custom_headers
    end
  end
end
