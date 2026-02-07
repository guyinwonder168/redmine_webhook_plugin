module RedmineWebhookPlugin
  module Webhook
    class RetryPolicy
      DEFAULT_CONFIG = {
        "max_attempts" => 5,
        "base_delay" => 60,
        "max_delay" => 3600,
        "retryable_statuses" => [408, 429, 500, 502, 503, 504]
      }.freeze

      RETRYABLE_ERROR_CODES = %w[
        connection_timeout
        read_timeout
        connection_refused
        connection_reset
        dns_error
      ].freeze
      SSL_ERROR_CODE = "ssl_error".freeze

      attr_reader :max_attempts, :base_delay, :max_delay, :retryable_statuses

      def initialize(config = {})
        normalized_config = normalize_config_keys(config)
        @max_attempts = normalized_config["max_attempts"] || DEFAULT_CONFIG["max_attempts"]
        @base_delay = normalized_config["base_delay"] || DEFAULT_CONFIG["base_delay"]
        @max_delay = normalized_config["max_delay"] || DEFAULT_CONFIG["max_delay"]
        @retryable_statuses = normalized_config["retryable_statuses"] || DEFAULT_CONFIG["retryable_statuses"]

        freeze
      end

      def ==(other)
        other.is_a?(RetryPolicy) &&
          max_attempts == other.max_attempts &&
          base_delay == other.base_delay &&
          max_delay == other.max_delay &&
          retryable_statuses == other.retryable_statuses
      end
      alias eql? ==

      def hash
        [max_attempts, base_delay, max_delay, retryable_statuses].hash
      end

      def to_h
        {
          "max_attempts" => max_attempts,
          "base_delay" => base_delay,
          "max_delay" => max_delay,
          "retryable_statuses" => retryable_statuses
        }
      end

      def retryable?(http_status:, error_code:, ssl_verify: true)
        retryable_status?(http_status) || retryable_error_code?(error_code, ssl_verify)
      end

      def should_retry?(attempt_count:, http_status:, error_code:, ssl_verify: true)
        return false if attempt_count >= max_attempts

        retryable?(http_status: http_status, error_code: error_code, ssl_verify: ssl_verify)
      end

      def next_delay(attempt_number:, jitter: true)
        delay = base_delay * (2 ** attempt_number.to_i)
        delay = [delay, max_delay].min
        jitter_factor = jitter_factor_for(jitter)
        jittered_delay = (delay * jitter_factor).round

        [jittered_delay, max_delay].min
      end

      def next_retry_at(attempt_number:, now: Time.current, jitter: true)
        now + next_delay(attempt_number: attempt_number, jitter: jitter)
      end

      private

      def retryable_status?(http_status)
        return false if http_status.nil?

        retryable_statuses.include?(http_status)
      end

      def retryable_error_code?(error_code, ssl_verify)
        return false if error_code.nil?

        code = error_code.to_s
        return true if RETRYABLE_ERROR_CODES.include?(code)
        return true if code == SSL_ERROR_CODE && !ssl_verify

        false
      end

      def jitter_factor_for(jitter)
        return 1.0 unless jitter
        return jitter.to_f if jitter.is_a?(Numeric)

        rand(0.8..1.2)
      end

      def normalize_config_keys(config)
        return DEFAULT_CONFIG if config.nil? || config.empty?

        config.transform_keys { |key| key.to_s }
      end
    end
  end
end
