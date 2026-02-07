module RedmineWebhookPlugin
  module Webhook
    class ErrorClassifier
      EXCEPTION_MAPPINGS = {
        Timeout::Error => "connection_timeout",
        Net::OpenTimeout => "connection_timeout",
        Net::ReadTimeout => "read_timeout",
        Errno::ECONNREFUSED => "connection_refused",
        Errno::ECONNRESET => "connection_reset",
        SocketError => "dns_error",
        OpenSSL::SSL::SSLError => "ssl_error"
      }.freeze

      def self.classify(exception)
        return nil if exception.nil?
        return "read_timeout" if exception.is_a?(Net::ReadTimeout)

        mapping = EXCEPTION_MAPPINGS.find { |klass, _| exception.is_a?(klass) }
        return mapping.last if mapping

        "unknown_error"
      end

      def self.classify_http_status(status)
        return nil if status.nil?

        return nil if status >= 200 && status < 300
        return "client_error" if status >= 400 && status < 500
        return "server_error" if status >= 500 && status < 600

        nil
      end
    end
  end
end
