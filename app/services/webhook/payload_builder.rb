module RedmineWebhookPlugin
  module Webhook
    class PayloadBuilder
    SCHEMA_VERSION = "1.0".freeze
    MAX_PAYLOAD_SIZE = 1_048_576  # 1MB
    MAX_CHANGES = 100

    SKIP_ATTRIBUTES = %w[
      updated_on created_on lock_version lft rgt root_id
      updated_at created_at
    ].freeze

    SENSITIVE_CUSTOM_FIELDS = %w[
      api_key password secret token private_key auth_token
      credential secret_key api_token access_token
    ].freeze

    VALID_EVENT_TYPES = %w[issue time_entry].freeze
    VALID_ACTIONS = %w[created updated deleted].freeze
    VALID_PAYLOAD_MODES = %w[minimal full].freeze

    class PayloadTooLargeError < StandardError; end

    attr_reader :event_data, :payload_mode

    def initialize(event_data, payload_mode = "minimal")
      raise ArgumentError, "event_data must be a Hash" unless event_data.is_a?(Hash)
      raise ArgumentError, "event_type is required" unless event_data[:event_type].present?
      raise ArgumentError, "action is required" unless event_data[:action].present?

      unless VALID_EVENT_TYPES.include?(event_data[:event_type])
        raise ArgumentError, "Invalid event_type: #{event_data[:event_type]}"
      end

      unless VALID_ACTIONS.include?(event_data[:action])
        raise ArgumentError, "Invalid action: #{event_data[:action]}"
      end

      unless VALID_PAYLOAD_MODES.include?(payload_mode)
        raise ArgumentError, "Invalid payload_mode: #{payload_mode}"
      end

      @event_data = event_data
      @payload_mode = payload_mode
      @base_url = nil
    end

    def build
      payload = build_envelope
      payload[:actor] = serialize_actor(event_data[:actor])
      payload[:project] = serialize_project(event_data[:project])
      payload.merge!(build_resource_data)
      payload[:changes] = build_changes_for_event if update_action?
      payload[:last_note] = serialize_journal(event_data[:journal]) if event_data[:journal]
      enforce_size_limit(payload)
    end

    private

    def build_envelope
      {
        event_id: event_data[:event_id],
        event_type: event_data[:event_type],
        action: event_data[:action],
        occurred_at: format_timestamp(event_data[:occurred_at]),
        sequence_number: event_data[:sequence_number],
        delivery_mode: payload_mode,
        schema_version: SCHEMA_VERSION
      }
    end

    def build_resource_data
      case event_data[:event_type]
      when "issue"
        build_issue_data
      when "time_entry"
        build_time_entry_data
      else
        {}
      end
    end

    def build_issue_data
      if delete_action?
        snapshot = event_data[:resource_snapshot]
        return {} if snapshot.nil?
        { issue: build_delete_snapshot(snapshot, "issue") }
      else
        resource = event_data[:resource]
        return {} if resource.nil?
        issue_data = full_mode? ? serialize_issue_full(resource) : serialize_issue_minimal(resource)
        { issue: issue_data }
      end
    end

    def delete_action?
      event_data[:action] == "deleted"
    end

    def full_mode?
      payload_mode == "full"
    end

    def update_action?
      event_data[:action] == "updated"
    end

    def build_changes_for_event
      saved_changes = event_data[:saved_changes].presence || event_data[:changes]
      custom_field_changes = event_data[:custom_field_changes]

      changes = []
      changes.concat(build_changes(saved_changes, event_data[:resource])) if saved_changes.present?
      changes.concat(build_custom_field_changes(custom_field_changes)) if custom_field_changes.present?
      changes
    end

    def build_custom_field_changes(custom_field_changes)
      return [] if custom_field_changes.nil? || custom_field_changes.empty?

      custom_field_changes.map do |cf_id, change_data|
        {
          field: "custom_field:#{cf_id}",
          kind: "custom_field",
          name: change_data[:name],
          old: { raw: change_data[:old], text: change_data[:old] },
          new: { raw: change_data[:new], text: change_data[:new] }
        }
      end
    end

    def build_delete_snapshot(snapshot, resource_type)
      case resource_type
      when "issue"
        build_issue_delete_snapshot(snapshot)
      when "time_entry"
        build_time_entry_delete_snapshot(snapshot)
      else
        { snapshot_type: "pre_delete" }
      end
    end

    def build_issue_delete_snapshot(snapshot)
      {
        snapshot_type: "pre_delete",
        id: snapshot[:id],
        subject: snapshot[:subject],
        description: snapshot[:description],
        tracker: { id: snapshot[:tracker_id], name: snapshot[:tracker_name] },
        status: { id: snapshot[:status_id], name: snapshot[:status_name] },
        priority: { id: snapshot[:priority_id], name: snapshot[:priority_name] },
        author: {
          id: snapshot[:author_id],
          login: snapshot[:author_login],
          name: snapshot[:author_name]
        },
        assigned_to: snapshot[:assigned_to_id] ? {
          id: snapshot[:assigned_to_id],
          login: snapshot[:assigned_to_login],
          name: snapshot[:assigned_to_name]
        } : nil,
        project: {
          id: snapshot[:project_id],
          identifier: snapshot[:project_identifier],
          name: snapshot[:project_name]
        },
        start_date: snapshot[:start_date],
        due_date: snapshot[:due_date],
        done_ratio: snapshot[:done_ratio],
        estimated_hours: snapshot[:estimated_hours]
      }
    end

    def build_time_entry_delete_snapshot(snapshot)
      {
        snapshot_type: "pre_delete",
        id: snapshot[:id],
        hours: snapshot[:hours],
        spent_on: snapshot[:spent_on],
        comments: snapshot[:comments],
        activity: { id: snapshot[:activity_id], name: snapshot[:activity_name] },
        user: {
          id: snapshot[:user_id],
          login: snapshot[:user_login],
          name: snapshot[:user_name]
        },
        project: {
          id: snapshot[:project_id],
          identifier: snapshot[:project_identifier],
          name: snapshot[:project_name]
        },
        issue: snapshot[:issue_id] ? {
          id: snapshot[:issue_id],
          subject: snapshot[:issue_subject]
        } : nil
      }
    end

    def enforce_size_limit(payload)
      return payload if payload_size(payload) <= MAX_PAYLOAD_SIZE

      if payload[:changes].is_a?(Array) && payload[:changes].length > MAX_CHANGES
        payload[:changes] = payload[:changes].last(MAX_CHANGES)
        payload[:changes_truncated] = true
      end

      return payload if payload_size(payload) <= MAX_PAYLOAD_SIZE

      exclude_custom_fields!(payload)

      return payload if payload_size(payload) <= MAX_PAYLOAD_SIZE

      raise PayloadTooLargeError, "Payload exceeds maximum size of #{MAX_PAYLOAD_SIZE} bytes"
    end

    def payload_size(payload)
      payload.to_json.bytesize
    end

    def exclude_custom_fields!(payload)
      [:issue, :time_entry].each do |key|
        if payload[key].is_a?(Hash) && payload[key][:custom_fields].is_a?(Array)
          payload[key][:custom_fields] = []
          payload[:custom_fields_excluded] = true
        end
      end
    end

    def build_changes(saved_changes, _resource)
      return [] if saved_changes.nil? || saved_changes.empty?

      preload_ids = extract_referenced_ids(saved_changes)
      preloaded = preload_entities(preload_ids)

      changes = []
      saved_changes.each do |field, values|
        next if SKIP_ATTRIBUTES.include?(field.to_s)

        old_value, new_value = values
        changes << {
          field: field,
          kind: "attribute",
          old: resolve_value(field, old_value, preloaded),
          new: resolve_value(field, new_value, preloaded)
        }
      end

      changes
    end

    def build_time_entry_data
      if delete_action?
        snapshot = event_data[:resource_snapshot]
        return {} if snapshot.nil?
        { time_entry: build_delete_snapshot(snapshot, "time_entry") }
      else
        resource = event_data[:resource]
        return {} if resource.nil?
        time_entry_data = full_mode? ? serialize_time_entry_full(resource) : serialize_time_entry_minimal(resource)
        { time_entry: time_entry_data }
      end
    end

    def serialize_time_entry_minimal(time_entry)
      {
        id: time_entry.id,
        url: time_entry_web_url(time_entry),
        api_url: time_entry_api_url(time_entry),
        issue: serialize_time_entry_issue_minimal(time_entry.issue)
      }
    end

    def serialize_time_entry_issue_minimal(issue)
      return nil if issue.nil?

      {
        id: issue.id,
        subject: issue.subject
      }
    end

    def serialize_time_entry_full(time_entry)
      {
        id: time_entry.id,
        url: time_entry_web_url(time_entry),
        api_url: time_entry_api_url(time_entry),
        hours: time_entry.hours,
        spent_on: time_entry.spent_on&.iso8601,
        comments: time_entry.comments,
        activity: {
          id: time_entry.activity.id,
          name: time_entry.activity.name
        },
        user: serialize_actor(time_entry.user),
        issue: serialize_time_entry_issue_full(time_entry.issue),
        custom_fields: serialize_custom_fields(time_entry)
      }
    end

    def serialize_time_entry_issue_full(issue)
      return nil if issue.nil?

      {
        id: issue.id,
        subject: issue.subject,
        tracker: {
          id: issue.tracker.id,
          name: issue.tracker.name
        },
        project: {
          id: issue.project.id,
          identifier: issue.project.identifier,
          name: issue.project.name
        }
      }
    end

    def serialize_issue_minimal(issue)
      {
        id: issue.id,
        url: issue_web_url(issue),
        api_url: issue_api_url(issue),
        tracker: {
          id: issue.tracker.id,
          name: issue.tracker.name
        }
      }
    end

    def serialize_issue_full(issue)
      serialize_issue_minimal(issue).merge(
        subject: issue.subject,
        description: issue.description,
        status: {
          id: issue.status.id,
          name: issue.status.name
        },
        priority: {
          id: issue.priority.id,
          name: issue.priority.name
        },
        assigned_to: serialize_actor(issue.assigned_to),
        author: serialize_actor(issue.author),
        start_date: issue.start_date&.iso8601,
        due_date: issue.due_date&.iso8601,
        created_on: format_timestamp(issue.created_on),
        updated_on: format_timestamp(issue.updated_on),
        done_ratio: issue.done_ratio,
        estimated_hours: issue.estimated_hours,
        parent_issue: serialize_parent_issue(issue.parent),
        custom_fields: serialize_custom_fields(issue)
      )
    end

    def serialize_parent_issue(parent)
      return nil if parent.nil?
      { id: parent.id, subject: parent.subject }
    end

    def serialize_custom_fields(resource)
      return [] unless resource.respond_to?(:custom_field_values)

      resource.custom_field_values.map do |cfv|
        field_name = cfv.custom_field.name.downcase

        if SENSITIVE_CUSTOM_FIELDS.any? { |sf| field_name.include?(sf) }
          { id: cfv.custom_field.id, name: cfv.custom_field.name, value: "[FILTERED]" }
        else
          { id: cfv.custom_field.id, name: cfv.custom_field.name, value: cfv.value }
        end
      end
    end

    def serialize_journal(journal)
      return nil if journal.nil?

      {
        id: journal.id,
        notes: journal.notes,
        created_on: format_timestamp(journal.created_on)
      }
    end

    def serialize_actor(user)
      return nil if user.nil?

      if user.is_a?(Hash)
        { id: user[:id], login: user[:login], name: user[:name] }
      else
        { id: user.id, login: user.login, name: user.name }
      end
    end

    def serialize_project(project)
      return nil if project.nil?

      {
        id: project.id,
        identifier: project.identifier,
        name: project.name
      }
    end

    def format_timestamp(time)
      return nil if time.nil?
      time.utc.iso8601(3)
    end

    def base_url
      @base_url ||= "#{Setting.protocol}://#{Setting.host_name}"
    end

    def issue_web_url(issue)
      "#{base_url}/issues/#{issue.id}"
    end

    def issue_api_url(issue)
      "#{base_url}/issues/#{issue.id}.json"
    end

    def time_entry_web_url(time_entry)
      "#{base_url}/time_entries/#{time_entry.id}"
    end

    def time_entry_api_url(time_entry)
      "#{base_url}/time_entries/#{time_entry.id}.json"
    end

    def extract_referenced_ids(saved_changes)
      ids = {
        statuses: Set.new,
        priorities: Set.new,
        users: Set.new,
        projects: Set.new,
        trackers: Set.new,
        categories: Set.new,
        versions: Set.new,
        activities: Set.new
      }

      saved_changes.each do |field, (old_val, new_val)|
        case field.to_s
        when "status_id"
          ids[:statuses].add(old_val) if old_val
          ids[:statuses].add(new_val) if new_val
        when "priority_id"
          ids[:priorities].add(old_val) if old_val
          ids[:priorities].add(new_val) if new_val
        when "assigned_to_id", "author_id", "user_id"
          ids[:users].add(old_val) if old_val
          ids[:users].add(new_val) if new_val
        when "project_id"
          ids[:projects].add(old_val) if old_val
          ids[:projects].add(new_val) if new_val
        when "tracker_id"
          ids[:trackers].add(old_val) if old_val
          ids[:trackers].add(new_val) if new_val
        when "category_id"
          ids[:categories].add(old_val) if old_val
          ids[:categories].add(new_val) if new_val
        when "fixed_version_id"
          ids[:versions].add(old_val) if old_val
          ids[:versions].add(new_val) if new_val
        when "activity_id"
          ids[:activities].add(old_val) if old_val
          ids[:activities].add(new_val) if new_val
        end
      end

      ids.transform_values(&:to_a)
    end

    def preload_entities(ids)
      {
        statuses: preload_records(IssueStatus, ids[:statuses]),
        priorities: preload_records(IssuePriority, ids[:priorities]),
        users: preload_records(User, ids[:users]),
        projects: preload_records(Project, ids[:projects]),
        trackers: preload_records(Tracker, ids[:trackers]),
        categories: preload_records(IssueCategory, ids[:categories]),
        versions: preload_records(Version, ids[:versions]),
        activities: preload_records(TimeEntryActivity, ids[:activities])
      }.reject { |_key, value| value.empty? }
    end

    def preload_records(model, ids)
      return {} if ids.blank?

      model.where(id: ids).index_by(&:id)
    end

    def resolve_value(field, raw_value, preloaded)
      return { raw: nil, text: nil } if raw_value.nil?

      text_value = case field.to_s
                   when "status_id"
                     preloaded[:statuses][raw_value]&.name
                   when "priority_id"
                     preloaded[:priorities][raw_value]&.name
                   when "assigned_to_id", "author_id", "user_id"
                      user = preloaded[:users][raw_value]
                      user ? "#{user.name} (#{user.login})" : nil
                   when "category_id"
                     preloaded[:categories][raw_value]&.name
                   when "fixed_version_id"
                     preloaded[:versions][raw_value]&.name
                   when "activity_id"
                     preloaded[:activities][raw_value]&.name
                   when "tracker_id"
                     preloaded[:trackers][raw_value]&.name
                   when "project_id"
                     preloaded[:projects][raw_value]&.name
                   else
                     raw_value
                   end

      { raw: raw_value, text: text_value }
    end
  end
  end
end
