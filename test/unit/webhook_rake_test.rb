require File.expand_path("../test_helper", __dir__)
require "rake"

class WebhookRakeTest < ActiveSupport::TestCase
  setup do
    Rake.application = Rake::Application.new
    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all
  end

  test "webhook rake task is defined" do
    plugin_root = File.expand_path("../..", __dir__)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")
    assert Rake::Task.task_defined?("redmine:webhooks:process")
  end

  test "process task sends due deliveries" do
    plugin_root = File.expand_path("../..", __dir__)
    Rake::Task.define_task(:environment)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Rake Process",
      url: "https://example.test/webhooks",
      enabled: true
    )
    due_pending = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )
    due_failed = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      scheduled_at: 2.minutes.ago
    )
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      scheduled_at: 2.minutes.from_now
    )
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    )

    called_ids = []
    RedmineWebhookPlugin::Webhook::Sender.expects(:send).times(2).with do |delivery|
      called_ids << delivery.id
      true
    end

    Rake::Task["redmine:webhooks:process"].reenable
    Rake::Task["redmine:webhooks:process"].invoke

    assert_equal [due_pending.id, due_failed.id].sort, called_ids.sort
  end

  test "purge task is defined" do
    plugin_root = File.expand_path("../..", __dir__)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")
    assert Rake::Task.task_defined?("redmine:webhooks:purge")
  end

  test "purge removes old deliveries based on retention and preserves fresh ones" do
    plugin_root = File.expand_path("../..", __dir__)
    Rake::Task.define_task(:environment)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Purge Test",
      url: "https://example.test/webhooks",
      enabled: true
    )

    # Old successful delivery (10 days ago) - should be purged with default 7-day retention
    old_success = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      delivered_at: 10.days.ago
    )

    # Recent successful delivery (2 days ago) - should be preserved
    recent_success = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      delivered_at: 2.days.ago
    )

    # Old failed delivery (10 days ago) - should be purged
    old_failed = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      delivered_at: 10.days.ago
    )

    # Old dead delivery (10 days ago) - should be purged
    old_dead = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::DEAD,
      delivered_at: 10.days.ago
    )

    # Recent failed delivery (2 days ago) - should be preserved
    recent_failed = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      delivered_at: 2.days.ago
    )

    # Pending delivery (no delivered_at) - should be preserved
    pending_delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    # Use default retention (7 days for both)
    ENV.delete("RETENTION_DAYS_SUCCESS")
    ENV.delete("RETENTION_DAYS_FAILED")

    Rake::Task["redmine:webhooks:purge"].reenable
    Rake::Task["redmine:webhooks:purge"].invoke

    remaining_ids = RedmineWebhookPlugin::Webhook::Delivery.pluck(:id)

    # Old success, old failed, old dead should be purged
    assert_not_includes remaining_ids, old_success.id, "Old successful delivery should be purged"
    assert_not_includes remaining_ids, old_failed.id, "Old failed delivery should be purged"
    assert_not_includes remaining_ids, old_dead.id, "Old dead delivery should be purged"

    # Recent and pending should be preserved
    assert_includes remaining_ids, recent_success.id, "Recent successful delivery should be preserved"
    assert_includes remaining_ids, recent_failed.id, "Recent failed delivery should be preserved"
    assert_includes remaining_ids, pending_delivery.id, "Pending delivery should be preserved"
  end

  test "purge respects custom retention days from ENV" do
    plugin_root = File.expand_path("../..", __dir__)
    Rake::Task.define_task(:environment)
    load File.join(plugin_root, "lib", "tasks", "webhook.rake")

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Purge Custom",
      url: "https://example.test/webhooks",
      enabled: true
    )

    # 5-day-old successful delivery - should survive with 14-day retention
    mid_age_success = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      delivered_at: 5.days.ago
    )

    # 5-day-old failed delivery - should be purged with 3-day retention
    mid_age_failed = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      delivered_at: 5.days.ago
    )

    ENV["RETENTION_DAYS_SUCCESS"] = "14"
    ENV["RETENTION_DAYS_FAILED"] = "3"

    Rake::Task["redmine:webhooks:purge"].reenable
    Rake::Task["redmine:webhooks:purge"].invoke

    remaining_ids = RedmineWebhookPlugin::Webhook::Delivery.pluck(:id)

    assert_includes remaining_ids, mid_age_success.id, "5-day-old success should survive with 14-day retention"
    assert_not_includes remaining_ids, mid_age_failed.id, "5-day-old failed should be purged with 3-day retention"
  ensure
    ENV.delete("RETENTION_DAYS_SUCCESS")
    ENV.delete("RETENTION_DAYS_FAILED")
  end
end
