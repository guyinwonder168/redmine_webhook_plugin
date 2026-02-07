require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DeliveryJobTest < ActiveSupport::TestCase
  test "perform calls Sender for pending delivery" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Primary",
      url: "https://example.test/webhooks",
      enabled: true
    )
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: "{}"
    )

    RedmineWebhookPlugin::Webhook::Sender.expects(:send).with(
      kind_of(RedmineWebhookPlugin::Webhook::Delivery)
    )

    RedmineWebhookPlugin::Webhook::DeliveryJob.perform_now(delivery.id)
  end
end
