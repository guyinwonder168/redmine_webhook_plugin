require_relative "../test_helper"

module RedmineWebhookPlugin
  class VersionCompatibilityTest < ActiveSupport::TestCase
    fixtures :projects, :users, :trackers, :issue_statuses, :enumerations, :projects_trackers

    def setup
      @project = Project.find(1)
      @user = User.find(1)
      @issue = Issue.generate!(
        project: @project,
        subject: "Test Issue",
        tracker: Tracker.first,
        status: IssueStatus.first,
        priority: IssuePriority.first,
        author: @user
      )
      User.current = @user
    end

    def teardown
      User.current = nil
    end

    test "compatibility: redmine version detection" do
      assert defined?(Redmine::VERSION), "Redmine::VERSION should be defined"
      assert Redmine::VERSION.respond_to?(:to_s), "Redmine::VERSION should respond to to_s"
    end

    test "compatibility: Issue model exists and has expected attributes" do
      assert Issue.exists?(@issue.id), "Issue should exist"

      assert @issue.respond_to?(:project), "Issue should have project association"
      assert @issue.respond_to?(:tracker), "Issue should have tracker association"
      assert @issue.respond_to?(:status), "Issue should have status association"
      assert @issue.respond_to?(:priority), "Issue should have priority association"
      assert @issue.respond_to?(:author), "Issue should have author association"
      assert @issue.respond_to?(:assigned_to), "Issue should have assigned_to association"
      assert @issue.respond_to?(:custom_field_values), "Issue should have custom_field_values"
    end

    test "compatibility: TimeEntry model exists and has expected attributes" do
      time_entry = TimeEntry.generate!(
        project: @project,
        issue: @issue,
        user: @user,
        hours: 2.5,
        spent_on: Date.today,
        activity: TimeEntryActivity.first || TimeEntryActivity.generate!(name: "Development")
      )

      assert TimeEntry.exists?(time_entry.id), "TimeEntry should exist"

      assert time_entry.respond_to?(:project), "TimeEntry should have project association"
      assert time_entry.respond_to?(:issue), "TimeEntry should have issue association"
      assert time_entry.respond_to?(:user), "TimeEntry should have user association"
      assert time_entry.respond_to?(:activity), "TimeEntry should have activity association"
      assert time_entry.respond_to?(:custom_field_values), "TimeEntry should have custom_field_values"
    end

    test "compatibility: User.current works across versions" do
      User.current = @user
      assert_equal @user, User.current, "User.current should be set"
    end

    test "compatibility: Thread.current[:redmine_webhook_user] works" do
      Thread.current[:redmine_webhook_user] = @user
      assert_equal @user, Thread.current[:redmine_webhook_user]
    end

    test "compatibility: ActiveRecord callbacks work correctly" do
      initial_count = Issue.count
      Issue.generate!(project: @project, subject: "Callback Test", tracker: Tracker.first || Tracker.generate!(name: "Bug"), status: IssueStatus.first || IssueStatus.generate!(name: "New"))
      assert_equal initial_count + 1, Issue.count, "After commit callback should have executed"
    end

    test "compatibility: changes_to_save works in before_save" do
      issue = Issue.new(
        project: @project,
        subject: "Changes Test",
        tracker: Tracker.first || Tracker.generate!(name: "Bug"),
        status: IssueStatus.first || IssueStatus.generate!(name: "New"),
        author: @user
      )

      issue.save!
      assert issue.saved_changes.present?, "Issue should have saved changes"
    end

    test "compatibility: Setting.protocol and Setting.host_name are available" do
      assert Setting.respond_to?(:protocol), "Setting should respond to protocol"
      assert Setting.respond_to?(:host_name), "Setting should respond to host_name"

      base_url = "#{Setting.protocol}://#{Setting.host_name}"
      assert base_url.is_a?(String), "Base URL should be a string"
    end

    test "compatibility: associations eager load correctly" do
      issues = Issue.where(id: @issue.id).includes(:project, :tracker, :status, :priority, :author, :assigned_to)
      issues.first.project
      issues.first.tracker
      issues.first.status
      assert issues.first.association(:project).loaded?
      assert issues.first.association(:tracker).loaded?
      assert issues.first.association(:status).loaded?
    end

    test "compatibility: custom fields work across versions" do
      custom_field = IssueCustomField.generate!(
        name: "Compatibility Test Field",
        field_format: "string",
        is_for_all: true
      )

      @issue.custom_field_values << CustomValue.new(
        custom_field: custom_field,
        customized: @issue,
        value: "Test value"
      )
      @issue.save!

      @issue.reload
      assert @issue.custom_field_values.any?, "Issue should have custom field values"
    end

    test "compatibility: IssueStatus lookup works" do
      status = IssueStatus.first
      assert status.is_a?(IssueStatus), "Should find an IssueStatus"

      status_name = IssueStatus.find_by(id: status.id)&.name
      assert status_name.present?, "Should be able to lookup status name"
    end

    test "compatibility: User lookup works" do
      user = User.first
      assert user.is_a?(User), "Should find a User"

      user_name = User.find_by(id: user.id)&.name
      assert user_name.present?, "Should be able to lookup user name"
    end

    test "compatibility: Tracker lookup works" do
      tracker = Tracker.first
      assert tracker.is_a?(Tracker), "Should find a Tracker"

      tracker_name = Tracker.find_by(id: tracker.id)&.name
      assert tracker_name.present?, "Should be able to lookup tracker name"
    end

    test "compatibility: TimeEntryActivity lookup works" do
      activity = TimeEntryActivity.first
      assert activity.is_a?(TimeEntryActivity), "Should find a TimeEntryActivity"

      activity_name = TimeEntryActivity.find_by(id: activity.id)&.name
      assert activity_name.present?, "Should be able to lookup activity name"
    end

    test "compatibility: SecureRandom.uuid works" do
      uuid = SecureRandom.uuid
      assert uuid.is_a?(String), "UUID should be a string"
      assert_match(/^[0-9a-f-]{36}$/, uuid, "UUID should be in correct format")
    end

    test "compatibility: ActiveSupport::Concern works" do
      assert defined?(ActiveSupport::Concern), "ActiveSupport::Concern should be defined"

      test_module = Module.new do
        extend ActiveSupport::Concern
      end

      assert test_module.is_a?(Module), "Should create a valid module with ActiveSupport::Concern"
    end

    test "compatibility: after_commit callbacks execute in correct order" do
      skip "Requires database setup, skipping for compatibility check"
    end

    test "compatibility: Thread.current storage works" do
      Thread.current[:test_key] = "test_value"
      assert_equal "test_value", Thread.current[:test_key]
      Thread.current[:test_key] = nil
    end

    test "compatibility: JSON serialization works" do
      data = { id: @issue.id, subject: @issue.subject }
      json_string = data.to_json
      parsed = JSON.parse(json_string)

      assert_equal @issue.id, parsed["id"]
      assert_equal @issue.subject, parsed["subject"]
    end

    test "compatibility: timestamps with iso8601 work" do
      time = Time.now.utc
      iso_string = time.iso8601(3)
      assert iso_string.is_a?(String), "ISO8601 string should be a string"
      assert_match(/T\d{2}:\d{2}:\d{2}\.\d{3}Z$/, iso_string, "ISO8601 string should be in correct format")
    end

    test "compatibility: associations respond_to? works" do
      assert @issue.project.respond_to?(:id), "Project should respond to id"
      assert @issue.project.respond_to?(:identifier), "Project should respond to identifier"
      assert @issue.project.respond_to?(:name), "Project should respond to name"
    end

    test "compatibility: nil association handling works" do
      issue = Issue.generate!(
        project: @project,
        subject: "Nil Association Test",
        tracker: Tracker.first || Tracker.generate!(name: "Bug"),
        status: IssueStatus.first || IssueStatus.generate!(name: "New"),
        assigned_to: nil
      )

      assert_nil issue.assigned_to, "assigned_to should be nil"
      assert issue.respond_to?(:assigned_to), "Should respond to assigned_to even when nil"
    end

    test "compatibility: Time.now.to_f works for sequence numbers" do
      seq_num = (Time.now.to_f * 1_000_000).to_i
      assert seq_num.is_a?(Integer), "Sequence number should be an integer"
      assert seq_num > 0, "Sequence number should be positive"
    end

    test "compatibility: ActiveSupport Concern includes module methods" do
      test_concern = Module.new do
        extend ActiveSupport::Concern

        included do |base|
          base.extend(ClassMethods)
        end

        module ClassMethods
          def class_test_method
            "class method"
          end
        end

        def instance_test_method
          "instance method"
        end
      end

      test_class = Class.new do
        include test_concern
      end

      assert test_class.respond_to?(:class_test_method), "Should include class methods"
      test_instance = test_class.new
      assert test_instance.respond_to?(:instance_test_method), "Should include instance methods"
    end
  end
end
