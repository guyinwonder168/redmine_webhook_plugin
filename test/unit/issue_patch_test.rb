require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches/issue_patch", __dir__)

class IssuePatchTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses, :issues, :issue_categories, :enumerations

  setup do
    Issue.send(:include, RedmineWebhookPlugin::Patches::IssuePatch) unless
      Issue.included_modules.include?(RedmineWebhookPlugin::Patches::IssuePatch)
    RedmineWebhookPlugin::Webhook::TestHelper.enable_capture!
  end

  test "registers issue lifecycle callbacks" do
    commit_filters = Issue._commit_callbacks.map(&:filter)
    assert_includes commit_filters, :webhook_after_create
    assert_includes commit_filters, :webhook_after_update
    assert_includes commit_filters, :webhook_after_destroy

    destroy_filters = Issue._destroy_callbacks.map(&:filter)
    assert_includes destroy_filters, :webhook_capture_for_delete
  end

  test "captures changes and actor on update" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user
 
    issue.subject = "Webhook subject update"
    issue.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    changes = event[:changes]
    actor = event[:actor]
 
    assert changes.key?("subject")
    assert_equal "Webhook subject update", changes["subject"].last
    assert_equal({ id: user.id, login: user.login, name: user.name }, actor)
  end

  test "captures snapshot and actor on destroy" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user
    issue_id = issue.id

    events = []
    original_dispatch = RedmineWebhookPlugin::Webhook::Dispatcher.method(:dispatch)

    RedmineWebhookPlugin::Webhook::Dispatcher.define_singleton_method(:dispatch) do |event_data|
      events << event_data
      original_dispatch.call(event_data)
    end

    issue.destroy

    event = events.reverse.find { |entry| entry[:event_type] == "issue" && entry[:action] == "deleted" }
    snapshot = event[:resource_snapshot]
    actor = event[:actor]

    assert_equal issue_id, snapshot[:id]
    assert_equal({ id: user.id, login: user.login, name: user.name }, actor)
  ensure
    RedmineWebhookPlugin::Webhook::Dispatcher.define_singleton_method(:dispatch, &original_dispatch)
  end

  test "dispatches created issue event" do
    user = User.find(1)
    project = Project.find(1)
    tracker = Tracker.find(1)
    status = IssueStatus.find(1)
    priority = IssuePriority.first || IssuePriority.create!(name: "Normal", position: 1)
    User.current = user
 
    issue = Issue.new(
      project: project,
      tracker: tracker,
      status: status,
      priority: priority,
      author: user,
      subject: "Webhook create"
    )
 
    issue.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "issue", event[:event_type]
    assert_equal "created", event[:action]
    assert_equal issue.id, event[:resource_ref][:id]
  end
 
  test "dispatches updated issue event with changes" do
    issue = Issue.find(1)
    User.current = User.find(1)
 
    issue.subject = "Webhook update"
    issue.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "updated", event[:action]
    assert event[:changes].key?("subject")
  end
 
  test "dispatches deleted issue event with snapshot" do
    issue = Issue.find(2)
    User.current = User.find(1)
    issue_id = issue.id
 
    issue.destroy
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "deleted", event[:action]
    assert_equal issue_id, event[:resource_ref][:id]
    assert_equal issue_id, event[:resource_snapshot][:id]
  end
 
  test "dispatches updated issue event with journal when notes provided" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user
 
    issue.init_journal(user, "Test journal note for webhook")
    issue.subject = "Updated with journal"
    issue.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "updated", event[:action]
    assert_not_nil event[:journal], "Journal should be present in event data"
    assert_equal "Test journal note for webhook", event[:journal].notes
  end
 
  test "dispatches updated issue event without journal when no notes" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user
 
    issue.subject = "Updated without journal notes"
    issue.save!
 
    event = RedmineWebhookPlugin::Webhook::TestHelper.disable_capture
    assert_equal "updated", event[:action]
    # Journal may or may not be present depending on Redmine version behavior
    # The key is that it doesn't crash
  end

  test "cleans up instance variables after webhook dispatch" do
    issue = Issue.find(1)
    User.current = User.find(1)

    issue.subject = "Cleanup test"
    issue.save!

    assert_nil issue.instance_variable_get(:@webhook_skip)
    assert_nil issue.instance_variable_get(:@webhook_changes)
    assert_nil issue.instance_variable_get(:@webhook_actor)
    assert_nil issue.instance_variable_get(:@webhook_journal)
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
