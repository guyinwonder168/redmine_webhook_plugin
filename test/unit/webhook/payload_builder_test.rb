require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::PayloadBuilderTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :issue_statuses,
           :issues, :issue_categories, :enumerations, :time_entries, :journals

  test "PayloadBuilder class exists under RedmineWebhookPlugin::Webhook namespace" do
    assert defined?(RedmineWebhookPlugin::Webhook::PayloadBuilder), "RedmineWebhookPlugin::Webhook::PayloadBuilder should be defined"
  end

  test "initializes with event_data and payload_mode" do
    event_data = { event_type: "issue", action: "created" }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")

    assert_equal event_data, builder.event_data
    assert_equal "minimal", builder.payload_mode
  end

  test "payload_mode defaults to minimal" do
    event_data = { event_type: "issue", action: "created" }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data)

    assert_equal "minimal", builder.payload_mode
  end

  test "SCHEMA_VERSION constant is defined" do
    assert_equal "1.0", RedmineWebhookPlugin::Webhook::PayloadBuilder::SCHEMA_VERSION
  end

  test "build returns a Hash" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")

    result = builder.build
    assert_kind_of Hash, result
  end

  test "build includes envelope fields" do
    event_id = SecureRandom.uuid
    occurred_at = Time.current
    event_data = {
      event_id: event_id,
      event_type: "issue",
      action: "created",
      occurred_at: occurred_at,
      sequence_number: 12345,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_equal event_id, result[:event_id]
    assert_equal "issue", result[:event_type]
    assert_equal "created", result[:action]
    assert_equal occurred_at.utc.iso8601(3), result[:occurred_at]
    assert_equal 12345, result[:sequence_number]
    assert_equal "full", result[:delivery_mode]
    assert_equal "1.0", result[:schema_version]
  end

  test "build envelope handles nil sequence_number" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "time_entry",
      action: "updated",
      occurred_at: Time.current,
      sequence_number: nil,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:sequence_number]
  end

  test "build includes actor when present" do
    user = User.find(2)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: user,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:actor]
    assert_equal user.id, result[:actor][:id]
    assert_equal user.login, result[:actor][:login]
    assert_equal user.name, result[:actor][:name]
  end

  test "build sets actor to nil when not present" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:actor]
  end

  test "build includes project when present" do
    project = Project.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:project]
    assert_equal project.id, result[:project][:id]
    assert_equal project.identifier, result[:project][:identifier]
    assert_equal project.name, result[:project][:name]
  end

  test "build sets project to nil when not present" do
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: nil,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:project]
  end

  def setup
    @original_host_name = Setting.host_name
    @original_protocol = Setting.protocol
    Setting.host_name = "redmine.example.com"
    Setting.protocol = "https"
  end

  def teardown
    Setting.host_name = @original_host_name
    Setting.protocol = @original_protocol
  end

  test "issue_web_url generates correct URL" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    url = builder.send(:issue_web_url, issue)
    assert_equal "https://redmine.example.com/issues/#{issue.id}", url
  end

  test "issue_api_url generates correct URL" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    url = builder.send(:issue_api_url, issue)
    assert_equal "https://redmine.example.com/issues/#{issue.id}.json", url
  end

  test "time_entry_web_url generates correct URL" do
    time_entry = TimeEntry.first || create_time_entry
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    url = builder.send(:time_entry_web_url, time_entry)
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}", url
  end

  test "time_entry_api_url generates correct URL" do
    time_entry = TimeEntry.first || create_time_entry
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    url = builder.send(:time_entry_api_url, time_entry)
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}.json", url
  end

  test "base_url uses Setting.protocol and Setting.host_name" do
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    assert_equal "https://redmine.example.com", builder.send(:base_url)
  end

  test "serialize_issue_minimal includes id, url, api_url, and tracker" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:serialize_issue_minimal, issue)

    assert_equal issue.id, result[:id]
    assert_equal "https://redmine.example.com/issues/#{issue.id}", result[:url]
    assert_equal "https://redmine.example.com/issues/#{issue.id}.json", result[:api_url]
    assert_equal issue.tracker.id, result[:tracker][:id]
    assert_equal issue.tracker.name, result[:tracker][:name]
  end

  test "build includes issue data for issue events in minimal mode" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:issue]
    assert_equal issue.id, result[:issue][:id]
    assert_not_nil result[:issue][:tracker]
  end

  test "serialize_issue_full includes all minimal fields plus extended data" do
    issue = Issue.find(1)
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "full")

    result = builder.send(:serialize_issue_full, issue)

    assert_equal issue.id, result[:id]
    assert_not_nil result[:url]
    assert_not_nil result[:api_url]
    assert_not_nil result[:tracker]

    assert_equal issue.subject, result[:subject]
    assert_equal issue.description, result[:description]

    assert_equal issue.status.id, result[:status][:id]
    assert_equal issue.status.name, result[:status][:name]

    assert_equal issue.priority.id, result[:priority][:id]
    assert_equal issue.priority.name, result[:priority][:name]

    assert_equal issue.author.id, result[:author][:id]
    assert_equal issue.author.login, result[:author][:login]
    assert_equal issue.author.name, result[:author][:name]

    assert_equal issue.start_date&.iso8601, result[:start_date]
    assert_equal issue.due_date&.iso8601, result[:due_date]
    assert_equal issue.created_on.utc.iso8601(3), result[:created_on]
    assert_equal issue.updated_on.utc.iso8601(3), result[:updated_on]

    assert_equal issue.done_ratio, result[:done_ratio]
    assert_equal issue.estimated_hours, result[:estimated_hours]
  end

  test "build includes issue_full for full mode" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:issue]
    assert_equal issue.subject, result[:issue][:subject]
    assert_not_nil result[:issue][:status]
  end

  test "serialize_time_entry_minimal includes id, url, api_url, and issue" do
    time_entry = TimeEntry.first || create_time_entry
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:serialize_time_entry_minimal, time_entry)

    assert_equal time_entry.id, result[:id]
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}", result[:url]
    assert_equal "https://redmine.example.com/time_entries/#{time_entry.id}.json", result[:api_url]

    if time_entry.issue
      assert_not_nil result[:issue]
      assert_equal time_entry.issue.id, result[:issue][:id]
      assert_equal time_entry.issue.subject, result[:issue][:subject]
    else
      assert_nil result[:issue]
    end
  end

  test "serialize_time_entry_issue_minimal returns nil for nil issue" do
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")
    result = builder.send(:serialize_time_entry_issue_minimal, nil)

    assert_nil result
  end

  test "serialize_time_entry_full includes all minimal fields plus extended data" do
    time_entry = TimeEntry.first || create_time_entry
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "full")

    result = builder.send(:serialize_time_entry_full, time_entry)

    assert_equal time_entry.id, result[:id]
    assert_not_nil result[:url]
    assert_not_nil result[:api_url]

    assert_equal time_entry.hours, result[:hours]
    assert_equal time_entry.spent_on.iso8601, result[:spent_on]
    assert_equal time_entry.comments, result[:comments]

    assert_not_nil result[:activity]
    assert_equal time_entry.activity.id, result[:activity][:id]
    assert_equal time_entry.activity.name, result[:activity][:name]

    assert_not_nil result[:user]
    assert_equal time_entry.user.id, result[:user][:id]
    assert_equal time_entry.user.login, result[:user][:login]
    assert_equal time_entry.user.name, result[:user][:name]

    assert_kind_of Array, result[:custom_fields]
  end

  test "serialize_time_entry_full includes expanded issue with tracker and project" do
    time_entry = TimeEntry.first || create_time_entry
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "full")

    result = builder.send(:serialize_time_entry_full, time_entry)

    if time_entry.issue
      assert_not_nil result[:issue]
      assert_equal time_entry.issue.id, result[:issue][:id]
      assert_equal time_entry.issue.subject, result[:issue][:subject]
      assert_not_nil result[:issue][:tracker]
      assert_not_nil result[:issue][:project]
    end
  end

  test "build includes time_entry full data for full mode" do
    time_entry = TimeEntry.first || create_time_entry
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "time_entry",
      action: "created",
      occurred_at: Time.current,
      resource: time_entry,
      actor: time_entry.user,
      project: time_entry.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:time_entry]
    assert_not_nil result[:time_entry][:hours]
    assert_not_nil result[:time_entry][:activity]
    assert_not_nil result[:time_entry][:user]
  end

  test "resolve_value returns raw and text for status_id" do
    issue = Issue.find(1)
    status = IssueStatus.find(2)
    preloaded = { statuses: IssueStatus.where(id: [status.id]).index_by(&:id) }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "status_id", status.id, preloaded)

    assert_equal status.id, result[:raw]
    assert_equal status.name, result[:text]
  end

  test "resolve_value returns raw and text for priority_id" do
    issue = Issue.find(1)
    priority = IssuePriority.first
    preloaded = { priorities: IssuePriority.where(id: [priority.id]).index_by(&:id) }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "priority_id", priority.id, preloaded)

    assert_equal priority.id, result[:raw]
    assert_equal priority.name, result[:text]
  end

  test "resolve_value returns raw and text for assigned_to_id" do
    issue = Issue.find(1)
    user = User.find(2)
    preloaded = { users: User.where(id: [user.id]).index_by(&:id) }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "assigned_to_id", user.id, preloaded)

    assert_equal user.id, result[:raw]
    assert_equal "#{user.name} (#{user.login})", result[:text]
  end

  test "resolve_value returns raw and text for activity_id" do
    activity = TimeEntryActivity.first
    skip "No activities in fixtures" unless activity
    preloaded = { activities: TimeEntryActivity.where(id: [activity.id]).index_by(&:id) }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "activity_id", activity.id, preloaded)

    assert_equal activity.id, result[:raw]
    assert_equal activity.name, result[:text]
  end

  test "resolve_value handles nil gracefully" do
    preloaded = { statuses: {} }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "status_id", nil, preloaded)

    assert_nil result[:raw]
    assert_nil result[:text]
  end

  test "resolve_value returns raw only for unknown fields" do
    preloaded = {}
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "subject", "Test Subject", preloaded)

    assert_equal "Test Subject", result[:raw]
    assert_equal "Test Subject", result[:text]
  end

  test "resolve_value handles missing record gracefully" do
    preloaded = { statuses: IssueStatus.where(id: [1]).index_by(&:id) }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:resolve_value, "status_id", 99999, preloaded)

    assert_equal 99999, result[:raw]
    assert_nil result[:text]
  end

  test "build_changes creates changes array from saved_changes" do
    issue = Issue.find(1)
    saved_changes = {
      "status_id" => [1, 2],
      "subject" => ["Old subject", "New subject"],
      "updated_on" => [1.day.ago, Time.current]
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:build_changes, saved_changes, issue)

    assert_kind_of Array, result

    assert_not result.any? { |c| c[:field] == "updated_on" }

    status_change = result.find { |c| c[:field] == "status_id" }
    assert_not_nil status_change
    assert_equal "attribute", status_change[:kind]
    assert_equal 1, status_change[:old][:raw]
    assert_equal 2, status_change[:new][:raw]

    subject_change = result.find { |c| c[:field] == "subject" }
    assert_not_nil subject_change
    assert_equal "Old subject", subject_change[:old][:raw]
    assert_equal "New subject", subject_change[:new][:raw]
  end

  test "build_changes skips non-tracked attributes" do
    issue = Issue.find(1)
    saved_changes = {
      "updated_on" => [1.day.ago, Time.current],
      "created_on" => [1.day.ago, Time.current],
      "lock_version" => [1, 2],
      "lft" => [1, 2],
      "rgt" => [3, 4]
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:build_changes, saved_changes, issue)

    assert_empty result
  end

  test "build includes changes for update action" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "updated",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project,
      saved_changes: {
        "status_id" => [1, 2],
        "subject" => ["Old", "New"]
      }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_not_nil result[:changes]
    assert_kind_of Array, result[:changes]
    assert result[:changes].length >= 2
  end

  test "build does not include changes for created action" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:changes]
  end

  test "build_custom_field_changes creates changes for custom fields" do
    custom_field_changes = {
      "2" => { old: "old value", new: "new value", name: "Database" }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:build_custom_field_changes, custom_field_changes)

    assert_kind_of Array, result
    assert_equal 1, result.length

    cf_change = result.first
    assert_equal "custom_field:2", cf_change[:field]
    assert_equal "custom_field", cf_change[:kind]
    assert_equal "Database", cf_change[:name]
    assert_equal "old value", cf_change[:old][:raw]
    assert_equal "old value", cf_change[:old][:text]
    assert_equal "new value", cf_change[:new][:raw]
    assert_equal "new value", cf_change[:new][:text]
  end

  test "build_custom_field_changes handles empty changes" do
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:build_custom_field_changes, {})
    assert_empty result

    result = builder.send(:build_custom_field_changes, nil)
    assert_empty result
  end

  test "build includes custom field changes in changes array" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "updated",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project,
      saved_changes: { "status_id" => [1, 2] },
      custom_field_changes: {
        "2" => { old: "MySQL", new: "PostgreSQL", name: "Database" }
      }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    cf_change = result[:changes].find { |c| c[:kind] == "custom_field" }
    assert_not_nil cf_change
    assert_equal "custom_field:2", cf_change[:field]
    assert_equal "Database", cf_change[:name]
  end

  test "build_delete_snapshot creates snapshot from captured attributes" do
    snapshot = {
      id: 123,
      subject: "Deleted issue",
      tracker_id: 1,
      tracker_name: "Bug",
      project_id: 1,
      project_identifier: "ecookbook",
      project_name: "eCookbook",
      status_id: 1,
      status_name: "New",
      priority_id: 4,
      priority_name: "Normal",
      author_id: 2,
      author_login: "jsmith",
      author_name: "John Smith"
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "full")

    result = builder.send(:build_delete_snapshot, snapshot, "issue")

    assert_equal "pre_delete", result[:snapshot_type]
    assert_equal 123, result[:id]
    assert_equal "Deleted issue", result[:subject]
    assert_equal({ id: 1, name: "Bug" }, result[:tracker])
    assert_equal({ id: 1, name: "New" }, result[:status])
    assert_equal({ id: 4, name: "Normal" }, result[:priority])
  end

  test "build includes delete snapshot for deleted action" do
    snapshot = {
      id: 999,
      subject: "Issue to delete",
      tracker_id: 1,
      tracker_name: "Bug",
      project_id: 1,
      project_identifier: "ecookbook",
      project_name: "eCookbook",
      status_id: 1,
      status_name: "New",
      priority_id: 4,
      priority_name: "Normal",
      author_id: 2,
      author_login: "admin",
      author_name: "Admin"
    }
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "deleted",
      occurred_at: Time.current,
      resource: nil,
      resource_snapshot: snapshot,
      actor: nil,
      project: nil
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
    result = builder.build

    assert_not_nil result[:issue]
    assert_equal "pre_delete", result[:issue][:snapshot_type]
    assert_equal 999, result[:issue][:id]
  end

  test "build_delete_snapshot for time_entry" do
    snapshot = {
      id: 456,
      hours: 2.5,
      spent_on: Date.today.iso8601,
      comments: "Work done",
      activity_id: 9,
      activity_name: "Development",
      user_id: 2,
      user_login: "jsmith",
      user_name: "John Smith",
      project_id: 1,
      project_identifier: "ecookbook",
      project_name: "eCookbook",
      issue_id: 1,
      issue_subject: "Parent issue"
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "full")

    result = builder.send(:build_delete_snapshot, snapshot, "time_entry")

    assert_equal "pre_delete", result[:snapshot_type]
    assert_equal 456, result[:id]
    assert_equal 2.5, result[:hours]
    assert_equal({ id: 9, name: "Development" }, result[:activity])
  end

  test "MAX_PAYLOAD_SIZE constant is 1MB" do
    assert_equal 1_048_576, RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_PAYLOAD_SIZE
  end

  test "MAX_CHANGES constant is 100" do
    assert_equal 100, RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_CHANGES
  end

  test "enforce_size_limit does nothing when under limit" do
    payload = { event_id: "123", changes: [{ field: "a" }] }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:enforce_size_limit, payload)

    assert_equal payload, result
    assert_nil result[:changes_truncated]
    assert_nil result[:custom_fields_excluded]
  end

  test "enforce_size_limit truncates changes when over MAX_CHANGES and over size limit" do
    # Create changes that exceed 1MB total to trigger truncation
    large_changes = 150.times.map { |i| { field: "field_#{i}", old: "a" * 5000, new: "b" * 5000 } }
    payload = {
      event_id: "123",
      changes: large_changes,
      issue: { custom_fields: [] }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:enforce_size_limit, payload)

    assert_equal 100, result[:changes].length
    assert_equal true, result[:changes_truncated]
  end

  test "enforce_size_limit excludes custom_fields when still over limit" do
    huge_custom_fields = 600.times.map { |i| { id: i, value: "x" * 2000 } }
    payload = {
      event_id: "123",
      changes: [],
      issue: {
        id: 1,
        custom_fields: huge_custom_fields
      }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    result = builder.send(:enforce_size_limit, payload)

    assert_empty result[:issue][:custom_fields]
    assert_equal true, result[:custom_fields_excluded]
  end

  test "enforce_size_limit raises error when still over limit after all reductions" do
    huge_subject = "x" * 2_000_000
    payload = {
      event_id: "123",
      issue: {
        id: 1,
        subject: huge_subject,
        custom_fields: []
      },
      changes: []
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    error = assert_raises(RedmineWebhookPlugin::Webhook::PayloadBuilder::PayloadTooLargeError) do
      builder.send(:enforce_size_limit, payload)
    end

    assert_match(/exceeds maximum size/, error.message)
  end

  test "build applies size enforcement" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert result.to_json.bytesize < RedmineWebhookPlugin::Webhook::PayloadBuilder::MAX_PAYLOAD_SIZE
  end

  test "build includes journal info for issue updates when present" do
    issue = Issue.find(1)
    journal = issue.journals.first
    unless journal
      issue.init_journal(User.find(2), "Test note")
      issue.subject = "Changed for journal"
      issue.save!
      journal = issue.journals.last
    end

    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "updated",
      occurred_at: Time.current,
      resource: issue,
      actor: journal.user,
      project: issue.project,
      journal: journal,
      saved_changes: { "status_id" => [1, 2] }
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
     result = builder.build

    assert_not_nil result[:last_note]
    assert_equal journal.id, result[:last_note][:id]
    assert_equal journal.notes, result[:last_note][:notes]
  end

  test "build does not include journal when not present" do
    issue = Issue.find(1)
    event_data = {
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      occurred_at: Time.current,
      resource: issue,
      actor: nil,
      project: issue.project
    }
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
    result = builder.build

    assert_nil result[:last_note]
  end

  test "serialize_journal returns nil for nil journal" do
    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")
    result = builder.send(:serialize_journal, nil)
    assert_nil result
  end

  test "build_changes uses batch loading (no N+1 queries)" do
    status1 = IssueStatus.find(1)
    status2 = IssueStatus.find(2)
    priority1 = IssuePriority.first
    priority2 = IssuePriority.last
    user1 = User.find(1)
    user2 = User.find(2)
    project1 = Project.find(1)
    project2 = Project.find(2)
    tracker1 = Tracker.find(1)
    tracker2 = Tracker.find(2)

    saved_changes = {
      "status_id" => [status1.id, status2.id],
      "priority_id" => [priority1.id, priority2.id],
      "assigned_to_id" => [user1.id, user2.id],
      "author_id" => [user1.id, user2.id],
      "project_id" => [project1.id, project2.id],
      "tracker_id" => [tracker1.id, tracker2.id]
    }

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    query_count = 0
    ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      query_count += 1 if payload[:sql] =~ /SELECT.*FROM/
    end

    changes = builder.send(:build_changes, saved_changes, nil)

    ActiveSupport::Notifications.unsubscribe("sql.active_record")

    assert_kind_of Array, changes
    assert_equal 6, changes.length

    assert query_count < 10, "Expected batch loading (~8 queries), got #{query_count} queries"

    status_change = changes.find { |c| c[:field] == "status_id" }
    assert_equal status1.name, status_change[:old][:text]
    assert_equal status2.name, status_change[:new][:text]
  end

  test "extract_referenced_ids extracts all field value IDs" do
    saved_changes = {
      "status_id" => [1, 2],
      "priority_id" => [3, 4],
      "assigned_to_id" => [5, 6],
      "author_id" => [5, 7],
      "project_id" => [8, 9],
      "tracker_id" => [10, 11]
    }

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")
    result = builder.send(:extract_referenced_ids, saved_changes)

    assert_equal [1, 2], result[:statuses]
    assert_equal [3, 4], result[:priorities]
    assert_equal [5, 6, 7], result[:users].sort
    assert_equal [8, 9], result[:projects]
    assert_equal [10, 11], result[:trackers]
  end

  test "preload_entities batches queries by entity type" do
    ids = {
      statuses: [1, 2],
      priorities: [3, 4],
      users: [5, 6],
      projects: [1, 2],
      trackers: [1, 2],
      categories: [],
      versions: [],
      activities: []
    }

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new({event_type: "issue", action: "created"}, "minimal")

    query_count = 0
    ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      query_count += 1 if payload[:sql] =~ /SELECT.*FROM/
    end

    result = builder.send(:preload_entities, ids)

    ActiveSupport::Notifications.unsubscribe("sql.active_record")

    assert query_count <= 5, "Expected ~5 batch queries (one per non-empty type), got #{query_count}"

    assert_kind_of Hash, result[:statuses]
    assert_kind_of Hash, result[:priorities]
    assert_kind_of Hash, result[:users]
    assert_kind_of Hash, result[:projects]
    assert_kind_of Hash, result[:trackers]
    refute result.key?(:categories)
    refute result.key?(:versions)
    refute result.key?(:activities)
  end

  test "initialize raises on invalid event_type" do
    assert_raises(ArgumentError) do
      RedmineWebhookPlugin::Webhook::PayloadBuilder.new(
        { event_type: "invalid", action: "created" },
        "minimal"
      )
    end
  end

  test "initialize raises on missing action" do
    assert_raises(ArgumentError) do
      RedmineWebhookPlugin::Webhook::PayloadBuilder.new(
        { event_type: "issue" },
        "minimal"
      )
    end
  end

  test "initialize raises on invalid payload_mode" do
    assert_raises(ArgumentError) do
      RedmineWebhookPlugin::Webhook::PayloadBuilder.new(
        { event_type: "issue", action: "created" },
        "invalid"
      )
    end
  end

  test "filters sensitive custom field values" do
    issue = Issue.find(1)

    custom_field_value = Object.new
    custom_field_value.define_singleton_method(:custom_field) do
      field = Object.new
      field.define_singleton_method(:id) { 999 }
      field.define_singleton_method(:name) { "api_key" }
      field
    end
    custom_field_value.define_singleton_method(:value) { "super-secret-api-key-12345" }

    issue.define_singleton_method(:custom_field_values) do
      [custom_field_value]
    end

    builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(
      {
        event_id: SecureRandom.uuid,
        event_type: "issue",
        action: "created",
        occurred_at: Time.current,
        resource: issue,
        actor: nil,
        project: issue.project
      },
      "full"
    )
    result = builder.build

    assert result[:issue][:custom_fields].any?
    custom_field = result[:issue][:custom_fields].find { |cf| cf[:name] == "api_key" }
    assert_equal "[FILTERED]", custom_field[:value]
  end

  private

  def create_time_entry
    TimeEntry.create!(
      project: Project.find(1),
      user: User.find(2),
      issue: Issue.find(1),
      hours: 1.5,
      spent_on: Date.today,
      activity: TimeEntryActivity.first
    )
  end
end
