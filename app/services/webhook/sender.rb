module RedmineWebhookPlugin
  module Webhook
    class Sender
      def self.send(delivery)
        return if deliveries_paused?
        delivery.mark_delivering!("sender")

        endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find_by(id: delivery.endpoint_id)
        return if endpoint.nil?

        # Validate webhook_user if configured
        webhook_user = endpoint.webhook_user
        api_key = resolve_api_key(webhook_user)

        # Skip delivery if webhook_user is inactive
        if webhook_user && !webhook_user.active?
          delivery.mark_failed!("user_inactive", nil, "Webhook user is not active or locked")
          return
        end

        headers = RedmineWebhookPlugin::Webhook::HeadersBuilder.build(
          event_id: delivery.event_id,
          event_type: delivery.event_type,
          action: delivery.action,
          api_key: api_key,
          delivery_id: delivery.id,
          custom_headers: {}
        )

        client = RedmineWebhookPlugin::Webhook::HttpClient.new(
          timeout: endpoint.timeout,
          ssl_verify: endpoint.ssl_verify
        )

        payload = delivery.payload || "{}"
        result = client.post(url: endpoint.url, payload: payload, headers: headers)

      if result.success?
        delivery.mark_success!(result.http_status, result.response_body, result.duration_ms)
      else
        # Check if delivery should be retried
        retry_config = delivery.retry_policy_snapshot.is_a?(String) ? JSON.parse(delivery.retry_policy_snapshot) : (delivery.retry_policy_snapshot || {})
        retry_policy = RedmineWebhookPlugin::Webhook::RetryPolicy.new(retry_config)
        should_retry = retry_policy.should_retry?(
          attempt_count: delivery.attempt_count + 1,
          http_status: result.http_status,
          error_code: result.error_code,
          ssl_verify: endpoint.ssl_verify
        )

        if should_retry
          # Mark as failed with retry info
          next_retry_at = retry_policy.next_retry_at(attempt_number: delivery.attempt_count)
          delivery.update!(
            status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
            error_code: result.error_code,
            http_status: result.http_status,
            response_body_excerpt: result.response_body,
            duration_ms: result.duration_ms,
            attempt_count: delivery.attempt_count + 1,
            scheduled_at: next_retry_at,
            locked_by: nil,
            locked_at: nil
          )
        else
          # Mark as permanently failed
          delivery.mark_failed!(result.error_code, result.http_status, result.response_body)
        end
      end
    end

    private

      def self.resolve_api_key(user)
        return nil unless user
        RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(user)
      end

      def self.deliveries_paused?
        settings = Setting.plugin_redmine_webhook_plugin rescue {}
        settings.is_a?(Hash) && settings["deliveries_paused"] == "1"
      end
  end
end
end
