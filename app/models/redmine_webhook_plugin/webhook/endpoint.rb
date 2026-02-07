# app/models/redmine_webhook_plugin/webhook/endpoint.rb
module RedmineWebhookPlugin
  module Webhook
    class Endpoint < ActiveRecord::Base
      self.table_name = "webhook_endpoints"
      DEFAULT_RETRY_CONFIG = {
        "max_attempts" => 5,
        "base_delay" => 60,
        "max_delay" => 3600,
        "retryable_statuses" => [408, 429, 500, 502, 503, 504]
      }.freeze

      belongs_to :webhook_user, class_name: "User", optional: true
      has_many :deliveries, class_name: "RedmineWebhookPlugin::Webhook::Delivery", foreign_key: :endpoint_id, dependent: :nullify

      validates :name, presence: true, uniqueness: true
      validates :url, presence: true
      validate :url_must_be_http_or_https
      validate :webhook_user_must_be_active

      scope :enabled, -> { where(enabled: true) }

      def matches_event?(event_type, action, project_id)
        return false unless event_enabled?(event_type, action)
        return true if project_ids_array.empty?

        project_ids_array.include?(project_id.to_i)
      end

      def events_config
        val = read_attribute(:events_config)
        val.present? ? JSON.parse(val) : {}
      rescue JSON::ParserError
        {}
      end

      def events_config=(hash)
        write_attribute(:events_config, hash.to_json)
      end

      def project_ids_array
        val = read_attribute(:project_ids)
        val.present? ? JSON.parse(val) : []
      rescue JSON::ParserError
        []
      end

      def project_ids_array=(arr)
        write_attribute(:project_ids, arr.to_json)
      end

      def retry_config
        val = read_attribute(:retry_config)
        base = DEFAULT_RETRY_CONFIG.dup
        if val.present?
          begin
            base.merge!(JSON.parse(val))
          rescue JSON::ParserError
            # ignore parse errors, use defaults
          end
        end
        base
      end

      def retry_config=(hash)
        write_attribute(:retry_config, hash.to_json)
      end

      private

      def event_enabled?(event_type, action)
        config = events_config[event_type.to_s]
        return false unless config.is_a?(Hash)

        config[action.to_s] == true
      end

      def webhook_user_must_be_active
        return if webhook_user_id.blank?

        user = User.find_by(id: webhook_user_id)
        if user.nil? || !user.active?
          errors.add(:webhook_user_id, "must be an active user")
        end
      end

      def url_must_be_http_or_https
        return if url.blank?

        begin
          uri = URI.parse(url)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            errors.add(:url, "must be a valid HTTP or HTTPS URL")
          end
        rescue URI::InvalidURIError
          errors.add(:url, "must be a valid HTTP or HTTPS URL")
        end
      end
    end
  end
end
