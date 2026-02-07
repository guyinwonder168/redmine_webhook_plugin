require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/event_helpers", __dir__)

class EventHelpersTest < ActiveSupport::TestCase
  fixtures :users, :projects, :trackers, :issue_statuses, :issues, :enumerations, :projects_trackers

  Dummy = Class.new do
    include RedmineWebhookPlugin::EventHelpers
  end

  setup do
    Thread.current[:redmine_webhook_user] = nil
  end

  teardown do
    Thread.current[:redmine_webhook_user] = nil
    User.current = nil
  end

  test "generate_sequence_number returns integer microseconds" do
    helper = Dummy.new
    first = helper.generate_sequence_number
    second = helper.generate_sequence_number

    assert_kind_of Integer, first
    assert second >= first
  end

  test "resolve_actor returns nil for anonymous user" do
    helper = Dummy.new
    User.current = User.anonymous

    assert_nil helper.resolve_actor
  end

  test "resolve_actor returns hash for current user" do
    helper = Dummy.new
    user = User.find(1)
    User.current = user

    actor = helper.resolve_actor
    assert_equal({ id: user.id, login: user.login, name: user.name }, actor)
  end

  test "generate_event_id returns UUID" do
    helper = Dummy.new
    event_id = helper.generate_event_id

    assert_equal 36, event_id.length
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i, event_id)
  end

  test "resolve_actor uses thread-local storage" do
    helper = Dummy.new
    user1 = User.find(1)
    user2 = User.find(2)

    Thread.current[:redmine_webhook_user] = user1
    actor1 = helper.resolve_actor
    assert_equal user1.id, actor1[:id]

    Thread.current[:redmine_webhook_user] = user2
    actor2 = helper.resolve_actor
    assert_equal user2.id, actor2[:id]

    Thread.current[:redmine_webhook_user] = nil
  end

  test "resolve_actor is thread-safe across concurrent requests" do
    helper = Dummy.new
    user1 = User.find(1)
    user2 = User.find(2)
    results = []
    mutex = Mutex.new

    threads = [
      Thread.new do
        Thread.current[:redmine_webhook_user] = user1
        sleep 0.01
        actor = helper.resolve_actor
        mutex.synchronize { results << actor }
      end,
      Thread.new do
        Thread.current[:redmine_webhook_user] = user2
        sleep 0.01
        actor = helper.resolve_actor
        mutex.synchronize { results << actor }
      end
    ]

    threads.each(&:join)
    Thread.current[:redmine_webhook_user] = nil

    assert_equal 2, results.length
    user_ids = results.map { |a| a ? a[:id] : nil }
    assert_includes user_ids, user1.id
    assert_includes user_ids, user2.id
  end

  test "concurrent issue creation has correct actors" do
    user1 = User.find(1)
    user2 = User.find(2)
    project = Project.find(1)
    tracker = Tracker.find(1)
    status = IssueStatus.find(1)

    threads = []
    created_issues = []

    threads << Thread.new do
      Thread.current[:redmine_webhook_user] = user1
      issue = Issue.create!(
        project: project,
        tracker: tracker,
        status: status,
        author: user1,
        subject: "Thread test 1"
      )
      created_issues << { issue: issue, user: user1 }
    end

    threads << Thread.new do
      Thread.current[:redmine_webhook_user] = user2
      issue = Issue.create!(
        project: project,
        tracker: tracker,
        status: status,
        author: user2,
        subject: "Thread test 2"
      )
      created_issues << { issue: issue, user: user2 }
    end

    threads.each(&:join)

    assert_equal 2, created_issues.length
    created_issues.each do |data|
      assert_equal data[:user].id, data[:issue].author.id
    end
  end
end
