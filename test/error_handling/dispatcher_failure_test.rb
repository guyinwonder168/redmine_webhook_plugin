require File.expand_path("../../test/test_helper", __dir__)

class DispatcherFailureTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :issues

  test "webhook dispatch exception is caught and logged" do
    RedmineWebhookPlugin::Webhook::Dispatcher.stub(:dispatch) do |_event_data|
      raise StandardError, "Simulated network failure"
    end

    issue = Issue.find(1)
    User.current = User.find(1)

    assert_nothing_raised do
      issue.subject = "Test exception handling"
      issue.save!
    end

    assert_equal "Test exception handling", issue.reload.subject
  end

  test "webhook dispatch logs error to Rails logger" do
    logs = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(StringIO.new)
    Rails.logger.stub(:error) do |msg|
      logs << msg
    end

    RedmineWebhookPlugin::Webhook::Dispatcher.stub(:dispatch) do |_event_data|
      raise StandardError, "Test error"
    end

    issue = Issue.find(1)
    issue.subject = "Test logging"
    issue.save!

    assert logs.any? { |log| log.include?("Failed to dispatch") }
    assert logs.any? { |log| log.include?("Test error") }

    Rails.logger = original_logger
  end

  test "subsequent webhooks work after dispatch failure" do
    captured_events = []

    failure_count = 0

    RedmineWebhookPlugin::Webhook::Dispatcher.stub(:dispatch) do |event_data|
      failure_count += 1
      if failure_count == 1
        raise StandardError, "Failure #{failure_count}"
      else
        captured_events << event_data
      end
    end

    user = User.find(1)

    issue1 = Issue.create!(
      project: Project.find(1),
      tracker: Tracker.find(1),
      status: IssueStatus.find(1),
      author: user,
      subject: "First (should fail)"
    )

    issue2 = Issue.create!(
      project: Project.find(1),
      tracker: Tracker.find(1),
      status: IssueStatus.find(1),
      author: user,
      subject: "Second (should succeed)"
    )

    assert_equal 1, captured_events.length
    assert_equal "created", captured_events[0][:action]
  end
end
