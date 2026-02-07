require File.expand_path("../../test/test_helper", __dir__)

require File.expand_path("../../lib/redmine_webhook_plugin/patches/issue_patch", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches/time_entry_patch", __dir__)

module RedmineWebhookPlugin
  module Webhook
    TEST_CAPTURES = []
  end
end

class WebhookFlowTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  fixtures :projects, :users, :roles, :members, :member_roles, :projects_trackers,
           :trackers, :issue_statuses, :issue_categories, :issues, :time_entries, :enumerations

  setup do
    Issue.send(:include, RedmineWebhookPlugin::Patches::IssuePatch) unless
      Issue.included_modules.include?(RedmineWebhookPlugin::Patches::IssuePatch)
    TimeEntry.send(:include, RedmineWebhookPlugin::Patches::TimeEntryPatch) unless
      TimeEntry.included_modules.include?(RedmineWebhookPlugin::Patches::TimeEntryPatch)

    RedmineWebhookPlugin::Webhook::TEST_CAPTURES.clear
    @original_dispatch = RedmineWebhookPlugin::Webhook::Dispatcher.method(:dispatch)
    original_dispatch = @original_dispatch
    RedmineWebhookPlugin::Webhook::Dispatcher.define_singleton_method(:dispatch) do |event_data|
      # Capture events for this integration test without breaking other tests.
      RedmineWebhookPlugin::Webhook::TEST_CAPTURES << event_data
      original_dispatch.call(event_data)
    end
  end

  teardown do
    RedmineWebhookPlugin::Webhook::TEST_CAPTURES.clear
    RedmineWebhookPlugin::Webhook::Dispatcher.define_singleton_method(:dispatch, &@original_dispatch)
  end

  test "full webhook flow: patch -> dispatcher -> payload builder (issue create)" do
    user = User.find(1)
    project = Project.find(1)
    tracker = Tracker.find(1)
    status = IssueStatus.find(1)
    priority = IssuePriority.first || IssuePriority.create!(name: "Normal", position: 1)
    User.current = user

    issue = Issue.create!(
      project: project,
      tracker: tracker,
      status: status,
      priority: priority,
      author: user,
      subject: "Integration test"
    )

    captured = RedmineWebhookPlugin::Webhook::TEST_CAPTURES
    assert_equal 1, captured.length
    assert_equal "issue", captured[0][:event_type]
    assert_equal "created", captured[0][:action]
    assert_equal user.id, captured[0][:actor][:id]

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(captured[0], "minimal")
    payload = builder.build

    assert_equal issue.id, payload[:issue][:id]
    assert_not_nil payload[:issue][:tracker]
    assert payload.to_json.bytesize < RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_PAYLOAD_SIZE
  end

  test "full webhook flow: issue update with changes" do
    issue = Issue.find(1)
    User.current = User.find(1)

    # Ensure category validation passes even when fixtures vary by version.
    issue.category = nil
    issue.subject = "Updated with changes"
    issue.status_id = 2
    issue.save!

    captured = RedmineWebhookPlugin::Webhook::TEST_CAPTURES
    assert_equal "updated", captured[0][:action]
    assert captured[0][:changes].key?("subject")
    assert captured[0][:changes].key?("status_id")

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(captured[0], "full")
    payload = builder.build

    assert_not_nil payload[:changes]
    assert_equal "Updated with changes", payload[:changes].find { |c| c[:field] == "subject" }[:new][:text]
  end

  test "full webhook flow: issue delete with snapshot" do
    issue = Issue.find(1)
    User.current = User.find(1)
    issue_id = issue.id

    issue.destroy

    captured = RedmineWebhookPlugin::Webhook::TEST_CAPTURES
    assert_equal "deleted", captured[0][:action]
    assert_equal issue_id, captured[0][:resource_snapshot][:id]

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(captured[0], "full")
    payload = builder.build

    assert_not_nil payload[:issue]
    assert_equal issue_id, payload[:issue][:id]
  end

  test "full webhook flow: time entry lifecycle" do
    user = User.find(1)
    project = Project.find(1)
    issue = Issue.find(1)
    activity = TimeEntryActivity.first || TimeEntryActivity.create!(name: "Development", active: true)
    User.current = user

    entry = TimeEntry.create!(
      project: project,
      issue: issue,
      user: user,
      activity: activity,
      hours: 2.5,
      spent_on: Date.today
    )

    captured = RedmineWebhookPlugin::Webhook::TEST_CAPTURES
    assert_equal "created", captured[0][:action]

    entry.hours = 3.5
    entry.save!

    captured = RedmineWebhookPlugin::Webhook::TEST_CAPTURES
    assert_equal "updated", captured[1][:action]
    assert captured[1][:changes].key?("hours")

    entry.destroy

    captured = RedmineWebhookPlugin::Webhook::TEST_CAPTURES
    assert_equal "deleted", captured[2][:action]
    assert_equal entry.id, captured[2][:resource_snapshot][:id]
  end
end
