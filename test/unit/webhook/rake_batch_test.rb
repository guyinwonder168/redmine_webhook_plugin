require File.expand_path("../../test_helper", __dir__)
require "rake"

class RedmineWebhookPlugin::Webhook::RakeBatchTest < ActiveSupport::TestCase
  setup do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    plugin_root = File.expand_path("../../..", __dir__)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")

    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all

    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Batch", url: "https://example.com", enabled: true
    )
    60.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        endpoint_id: @endpoint.id, event_id: "e-#{i}", event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
      )
    end
  end

  test "process task respects BATCH_SIZE limit" do
    ENV['BATCH_SIZE'] = '10'
    called_ids = []
    RedmineWebhookPlugin::Webhook::Sender.expects(:send).times(10).with do |delivery|
      called_ids << delivery.id
    end
    Rake::Task["redmine:webhooks:process"].reenable
    Rake::Task["redmine:webhooks:process"].invoke

    assert_equal 10, called_ids.length, "Should only process BATCH_SIZE deliveries"
  ensure
    ENV.delete('BATCH_SIZE')
  end

  test "process task defaults to 50 batch size" do
    ENV.delete('BATCH_SIZE')
    called_ids = []
    RedmineWebhookPlugin::Webhook::Sender.expects(:send).times(50).with do |delivery|
      called_ids << delivery.id
    end
    Rake::Task["redmine:webhooks:process"].reenable
    Rake::Task["redmine:webhooks:process"].invoke

    assert_equal 50, called_ids.length, "Should default to 50 deliveries"
  end
end
