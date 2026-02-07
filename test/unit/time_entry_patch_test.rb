require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches/time_entry_patch", __dir__)


class TimeEntryPatchTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  fixtures :projects, :users, :issues, :time_entries, :enumerations, :trackers, :projects_trackers, :issue_statuses, :issue_categories

  setup do
    TimeEntry.send(:include, RedmineWebhookPlugin::Patches::TimeEntryPatch) unless
      TimeEntry.included_modules.include?(RedmineWebhookPlugin::Patches::TimeEntryPatch)
    RedmineWebhookPlugin::Webhook::TestHelper.enable_capture!
  end

  test "registers time entry callbacks" do
    commit_filters = TimeEntry._commit_callbacks.map(&:filter)
    assert_includes commit_filters, :webhook_after_create
    assert_includes commit_filters, :webhook_after_update
    assert_includes commit_filters, :webhook_after_destroy

    save_filters = TimeEntry._save_callbacks.map(&:filter)
    assert_includes save_filters, :webhook_capture_changes

    destroy_filters = TimeEntry._destroy_callbacks.map(&:filter)
    assert_includes destroy_filters, :webhook_capture_for_delete
  end

  test "dispatches created time entry event" do
    user = User.find(1)
    project = Project.find(1)
    issue = Issue.find(1)
    activity = TimeEntryActivity.first || TimeEntryActivity.create!(name: "Development", active: true)
    User.current = user
 
    entry = TimeEntry.new(
      project: project,
      issue: issue,
      user: user,
      activity: activity,
      hours: 1.5,
      spent_on: Date.today
    )
 
    entry.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "time_entry", event[:event_type]
    assert_equal "created", event[:action]
    assert_equal entry.id, event[:resource_ref][:id]
    assert_equal issue.id, event[:resource_ref][:issue_id]
    assert_equal project.id, event[:resource_ref][:project_id]
  end
 
  test "dispatches updated time entry event with changes" do
    entry = TimeEntry.find(1)
    User.current = User.find(1)
 
    entry.hours = entry.hours + 1.0
    entry.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "updated", event[:action]
    assert event[:changes].key?("hours")
  end
 
  test "dispatches deleted time entry event with snapshot" do
    entry = TimeEntry.find(1)
    User.current = User.find(1)
    entry_id = entry.id
 
    entry.destroy
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "deleted", event[:action]
    assert_equal entry_id, event[:resource_ref][:id]
    assert_equal entry_id, event[:resource_snapshot][:id]
  end
 
  test "handles nil issue on create" do
    user = User.find(1)
    project = Project.find(1)
    activity = TimeEntryActivity.first || TimeEntryActivity.create!(name: "Development", active: true)
    User.current = user
 
    entry = TimeEntry.new(
      project: project,
      issue: nil,
      user: user,
      activity: activity,
      hours: 0.5,
      spent_on: Date.today
    )
 
    entry.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "created", event[:action]
    assert_nil event[:resource_ref][:issue_id]
    assert_equal project.id, event[:resource_ref][:project_id]
  end

  test "cleans up instance variables after webhook dispatch" do
    entry = TimeEntry.find(1)
    User.current = User.find(1)

    entry.hours = entry.hours + 1.0
    entry.save!

    assert_nil entry.instance_variable_get(:@webhook_skip)
    assert_nil entry.instance_variable_get(:@webhook_changes)
    assert_nil entry.instance_variable_get(:@webhook_actor)
  end

  test "dispatcher stub is thread-safe" do
    event1 = { event_id: "1", event_type: "issue", action: "created" }
    event2 = { event_id: "2", event_type: "time_entry", action: "updated" }

    # Use TEST_CAPTURES array pattern for thread-safety test
    RedmineWebhookPlugin::Webhook::TEST_CAPTURES ||= []
    RedmineWebhookPlugin::Webhook::TEST_CAPTURES.clear
    @original_dispatch = RedmineWebhookPlugin::Webhook::Dispatcher.method(:dispatch)
    original_dispatch = @original_dispatch
    RedmineWebhookPlugin::Webhook::Dispatcher.define_singleton_method(:dispatch) do |event_data|
      RedmineWebhookPlugin::Webhook::TEST_CAPTURES << event_data
      original_dispatch.call(event_data)
    end

    results = []
    threads = []

    threads << Thread.new do
      RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event1)
    end

    threads << Thread.new do
      RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event2)
    end

    threads.each(&:join)

    # Restore original dispatch
    RedmineWebhookPlugin::Webhook::Dispatcher.define_singleton_method(:dispatch, &@original_dispatch)
    results = RedmineWebhookPlugin::Webhook::TEST_CAPTURES.dup

    assert_equal 2, results.length
    assert_equal %w[1 2], results.map { |event| event[:event_id] }.sort
  end
end
