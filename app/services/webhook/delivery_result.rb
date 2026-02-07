# app/services/webhook/delivery_result.rb
module RedmineWebhookPlugin
  module Webhook
    class DeliveryResult
      MAX_BODY_BYTES = 2048

      attr_reader :http_status, :response_body, :error_code, :error_message, :duration_ms, :final_url

      def self.success(http_status:, response_body: nil, duration_ms: nil, final_url: nil)
        new(
          http_status: http_status,
          response_body: response_body,
          duration_ms: duration_ms,
          final_url: final_url,
          success: true
        )
      end

      def self.failure(error_code:, error_message: nil, duration_ms: nil, final_url: nil, http_status: nil, response_body: nil)
        new(
          http_status: http_status,
          response_body: response_body,
          error_code: error_code,
          error_message: error_message,
          duration_ms: duration_ms,
          final_url: final_url,
          success: false
        )
      end

      def initialize(http_status:, response_body:, duration_ms:, final_url:, success:, error_code: nil, error_message: nil)
        @http_status = http_status
        @response_body = _truncate_body(response_body)
        @error_code = error_code
        @error_message = error_message
        @duration_ms = duration_ms
        @final_url = final_url
        @success = success
      end

      def success?
        @success
      end

      private

      def _truncate_body(body)
        return body unless body.is_a?(String)
        return body if body.bytesize <= MAX_BODY_BYTES

        body.byteslice(0, MAX_BODY_BYTES)
      end
    end
  end
end
