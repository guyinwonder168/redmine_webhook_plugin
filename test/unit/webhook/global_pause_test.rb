require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::GlobalPauseTest < ActiveSupport::TestCase
  fixtures :users, :projects, :trackers, :projects_trackers, :issue_statuses,
           :issues, :enumerations

  def setup
    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Pause Test", url: "https://example.com", enabled: true,
      events_config: { "issue" => { "created" => true } },
      project_ids: [1]
    )
  end

  test "Dispatcher does not create deliveries when paused" do
    Setting.plugin_redmine_webhook_plugin = { "deliveries_paused" => "1" }

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      project_id: 1,
      occurred_at: Time.current,
      resource: Issue.find(1),
      actor: User.find(1),
      project: Project.find(1)
    }
    deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)

    assert_empty deliveries, "Should not create deliveries when paused"
  ensure
    Setting.plugin_redmine_webhook_plugin = {
      "execution_mode" => "auto",
      "retention_days_success" => "7",
      "retention_days_failed" => "7",
      "deliveries_paused" => "0"
    }
  end

  test "Sender does not send when paused" do
    Setting.plugin_redmine_webhook_plugin = { "deliveries_paused" => "1" }
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: @endpoint.id, event_id: SecureRandom.uuid,
      event_type: "issue", action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery.reload.status,
      "Delivery should remain PENDING when globally paused"
  ensure
    Setting.plugin_redmine_webhook_plugin = {
      "execution_mode" => "auto",
      "retention_days_success" => "7",
      "retention_days_failed" => "7",
      "deliveries_paused" => "0"
    }
  end
end
