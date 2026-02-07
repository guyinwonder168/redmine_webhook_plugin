module RedmineWebhookPlugin
  module Webhook
    class DeliveryJob < ActiveJob::Base
      queue_as :webhooks

      def perform(delivery_id)
        delivery = RedmineWebhookPlugin::Webhook::Delivery.find_by(id: delivery_id)
        return unless delivery
        return unless delivery.can_retry?

        RedmineWebhookPlugin::Webhook::Sender.send(delivery)
      end
    end
  end
end
