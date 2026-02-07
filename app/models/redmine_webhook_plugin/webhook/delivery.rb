# app/models/redmine_webhook_plugin/webhook/delivery.rb
module RedmineWebhookPlugin
  module Webhook
    class Delivery < ActiveRecord::Base
      self.table_name = "webhook_deliveries"
      PENDING = "pending".freeze
      DELIVERING = "delivering".freeze
      SUCCESS = "success".freeze
      FAILED = "failed".freeze
      DEAD = "dead".freeze
      ENDPOINT_DELETED = "endpoint_deleted".freeze

      STATUSES = [PENDING, DELIVERING, SUCCESS, FAILED, DEAD, ENDPOINT_DELETED].freeze

      belongs_to :endpoint, class_name: "RedmineWebhookPlugin::Webhook::Endpoint", optional: true
      belongs_to :webhook_user, class_name: "User", optional: true

      validates :event_id, presence: true
      validates :event_type, presence: true
      validates :action, presence: true
      validates :status, inclusion: { in: STATUSES }

      scope :pending, -> { where(status: PENDING) }
      scope :failed, -> { where(status: FAILED) }
      scope :due, -> { where("scheduled_at IS NULL OR scheduled_at <= ?", Time.current) }

      def can_retry?
        [PENDING, FAILED].include?(status)
      end

      def mark_delivering!(runner_id)
        update!(
          status: DELIVERING,
          locked_by: runner_id,
          locked_at: Time.current
        )
      end

      def mark_success!(http_status, response_excerpt, duration_ms)
        update!(
          status: SUCCESS,
          http_status: http_status,
          response_body_excerpt: response_excerpt,
          duration_ms: duration_ms,
          delivered_at: Time.current,
          locked_by: nil,
          locked_at: nil
        )
      end

      def mark_failed!(error_code, http_status, response_excerpt)
        update!(
          status: FAILED,
          error_code: error_code,
          http_status: http_status,
          response_body_excerpt: response_excerpt,
          attempt_count: attempt_count + 1,
          locked_by: nil,
          locked_at: nil
        )
      end

      def mark_dead!
        update!(status: DEAD)
      end

      def reset_for_replay!
        update!(
          status: PENDING,
          attempt_count: 0,
          error_code: nil,
          http_status: nil,
          delivered_at: nil,
          response_body_excerpt: nil,
          duration_ms: nil,
          scheduled_at: nil,
          locked_by: nil,
          locked_at: nil
        )
      end
    end
  end
end
