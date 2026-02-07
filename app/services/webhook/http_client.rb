require "net/http"
require "uri"

module RedmineWebhookPlugin
  module Webhook
    class HttpClient
      MAX_REDIRECTS = 5
      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

      attr_reader :timeout, :ssl_verify

      def initialize(timeout:, ssl_verify: true)
        @timeout = timeout
        @ssl_verify = ssl_verify
      end

      def post(url:, payload:, headers: {})
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        current_url = url
        redirect_count = 0

        loop do
          response = perform_post(current_url, payload, headers)
          status = response.code.to_i

          unless redirect_status?(status)
            finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return build_result(response, current_url, started_at, finished_at)
          end

          location = response["location"]
          if location.nil? || location.strip.empty?
            finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return build_result(response, current_url, started_at, finished_at)
          end

          next_url = resolve_redirect_url(current_url, location)
          finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if insecure_redirect?(current_url, next_url)
            return DeliveryResult.failure(
              error_code: "insecure_redirect",
              duration_ms: ((finished_at - started_at) * 1000).round,
              final_url: next_url
            )
          end

          redirect_count += 1
          if redirect_count > MAX_REDIRECTS
            return DeliveryResult.failure(
              error_code: "too_many_redirects",
              duration_ms: ((finished_at - started_at) * 1000).round,
              final_url: next_url
            )
          end

          current_url = next_url
        end
      rescue StandardError => e
        finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        build_error_result(e, current_url, started_at, finished_at)
      end

      private

      def ssl_verify_mode
        return OpenSSL::SSL::VERIFY_NONE unless ssl_verify

        OpenSSL::SSL::VERIFY_PEER
      end

      def perform_post(url, payload, headers)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.verify_mode = ssl_verify_mode if http.use_ssl?

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = payload

        http.start { |client| client.request(request) }
      end

      def redirect_status?(status)
        REDIRECT_STATUSES.include?(status)
      end

      def resolve_redirect_url(current_url, location)
        current_uri = URI.parse(current_url)
        redirect_uri = URI.parse(location)

        return URI.join(current_uri.to_s, location).to_s if redirect_uri.relative?

        redirect_uri.to_s
      end

      def insecure_redirect?(current_url, next_url)
        current_scheme = URI.parse(current_url).scheme
        next_scheme = URI.parse(next_url).scheme

        current_scheme == "https" && next_scheme == "http"
      end

      def build_result(response, url, started_at, finished_at)
        duration_ms = ((finished_at - started_at) * 1000).round
        status = response.code.to_i
        body = response.body

        if status >= 200 && status < 300
          DeliveryResult.success(
            http_status: status,
            response_body: body,
            duration_ms: duration_ms,
            final_url: url
          )
        else
          DeliveryResult.failure(
            http_status: status,
            response_body: body,
            error_code: ErrorClassifier.classify_http_status(status),
            duration_ms: duration_ms,
            final_url: url
          )
        end
      end

      def build_error_result(exception, url, started_at, finished_at)
        duration_ms = ((finished_at - started_at) * 1000).round

        DeliveryResult.failure(
          error_code: ErrorClassifier.classify(exception),
          error_message: exception.message,
          duration_ms: duration_ms,
          final_url: url
        )
      end
    end
  end
end
