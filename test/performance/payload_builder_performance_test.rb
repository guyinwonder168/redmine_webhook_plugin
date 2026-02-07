require_relative "../test_helper"
require "benchmark"
require_relative "../../app/services/webhook/payload_builder"

module RedmineWebhookPlugin
  module Webhook
    class PayloadBuilderPerformanceTest < ActiveSupport::TestCase
      def setup
        @project = Project.generate!(identifier: "test", name: "Test Project")
        @issue = Issue.generate!(
          project: @project,
          subject: "Test Issue",
          description: "Test Description",
          tracker: Tracker.first || Tracker.generate!(name: "Bug"),
          status: IssueStatus.first || IssueStatus.generate!(name: "New"),
          priority: IssuePriority.first || IssuePriority.generate!(name: "Normal")
        )
        @user = User.generate!(login: "test_user", mail: "test@example.com")
        User.current = @user

        @base_event_data = {
          event_type: "issue",
          action: "created",
          event_id: SecureRandom.uuid,
          sequence_number: generate_sequence_number,
          occurred_at: Time.now,
          resource: @issue,
          project: @project,
          actor: resolve_actor,
          changes: { status_id: [1, 2] },
          saved_changes: { status_id: [1, 2] },
          custom_field_changes: {},
          journal: nil
        }
      end

      def teardown
        User.current = nil
      end

      test "performance: minimal mode payload generation under 5ms" do
        builder = PayloadBuilder.new(@base_event_data, "minimal")

        time = Benchmark.realtime do
          100.times do
            builder.build
          end
        end

        avg_time_ms = (time * 1000) / 100
        assert avg_time_ms < 5, "Average time #{avg_time_ms}ms exceeds 5ms threshold"
      end

      test "performance: full mode payload generation under 10ms" do
        builder = PayloadBuilder.new(@base_event_data, "full")

        time = Benchmark.realtime do
          100.times do
            builder.build
          end
        end

        avg_time_ms = (time * 1000) / 100
        assert avg_time_ms < 10, "Average time #{avg_time_ms}ms exceeds 10ms threshold"
      end

      test "performance: base_url caching reduces computation time" do
        builder = PayloadBuilder.new(@base_event_data, "minimal")

        time_without_cache = Benchmark.realtime do
          1000.times do |i|
            Setting.stubs(:protocol).returns("https")
            Setting.stubs(:host_name).returns("redmine#{i}.example.com")
            builder.send(:base_url_uncached)
          end
        end

        Setting.unstub(:protocol)
        Setting.unstub(:host_name)

        time_with_cache = Benchmark.realtime do
          1000.times do
            builder.send(:base_url)
          end
        end

        speedup = time_without_cache / time_with_cache
        assert speedup > 10, "Cache speedup #{speedup}x is less than 10x"
      end

      test "performance: payload size calculation is efficient" do
        builder = PayloadBuilder.new(@base_event_data, "full")
        payload = builder.build

        time = Benchmark.realtime do
          1000.times do
            builder.send(:payload_size, payload)
          end
        end

        avg_time_us = (time * 1_000_000) / 1000
        assert avg_time_us < 100, "Average time #{avg_time_us}μs exceeds 100μs threshold"
      end

      test "performance: large change set handling" do
        large_changes = (1..200).each_with_object({}) do |i, hash|
          hash["field_#{i}"] = ["value_#{i}_old", "value_#{i}_new"]
        end

        event_data = @base_event_data.merge(
          action: "updated",
          saved_changes: large_changes
        )

        builder = PayloadBuilder.new(event_data, "full")

        time = Benchmark.realtime do
          50.times do
            builder.build
          end
        end

        avg_time_ms = (time * 1000) / 50
        assert avg_time_ms < 50, "Average time #{avg_time_ms}ms exceeds 50ms threshold for 200 changes"
      end

      test "performance: delete event with snapshot" do
        event_data = {
          event_type: "issue",
          action: "deleted",
          event_id: SecureRandom.uuid,
          sequence_number: generate_sequence_number,
          occurred_at: Time.now,
          resource: { type: "issue", id: @issue.id, project_id: @project.id },
          resource_snapshot: {
            id: @issue.id,
            subject: @issue.subject,
            description: @issue.description,
            tracker_id: @issue.tracker_id,
            tracker_name: @issue.tracker.name,
            status_id: @issue.status_id,
            status_name: @issue.status.name,
            priority_id: @issue.priority_id,
            priority_name: @issue.priority.name,
            author_id: @issue.author_id,
            author_login: @issue.author.login,
            author_name: @issue.author.name,
            assigned_to_id: @issue.assigned_to_id,
            assigned_to_login: @issue.assigned_to&.login,
            assigned_to_name: @issue.assigned_to&.name,
            project_id: @project.id,
            project_identifier: @project.identifier,
            project_name: @project.name,
            start_date: @issue.start_date,
            due_date: @issue.due_date,
            done_ratio: @issue.done_ratio,
            estimated_hours: @issue.estimated_hours
          },
          project: @project,
          actor: resolve_actor
        }

        builder = PayloadBuilder.new(event_data, "full")

        time = Benchmark.realtime do
          100.times do
            builder.build
          end
        end

        avg_time_ms = (time * 1000) / 100
        assert avg_time_ms < 10, "Average time #{avg_time_ms}ms exceeds 10ms threshold for delete events"
      end

      test "performance: custom fields serialization" do
        custom_field = IssueCustomField.generate!(
          name: "Performance Test Field",
          field_format: "string",
          is_for_all: true
        )

        custom_value = CustomValue.new(
          custom_field: custom_field,
          customized: @issue,
          value: "Custom value 123"
        )
        @issue.custom_field_values << custom_value

        event_data = @base_event_data.merge(
          custom_field_changes: {
            custom_field.id => {
              name: custom_field.name,
              old: nil,
              new: "Custom value 123"
            }
          }
        )

        builder = PayloadBuilder.new(event_data, "full")

        time = Benchmark.realtime do
          100.times do
            builder.build
          end
        end

        avg_time_ms = (time * 1000) / 100
        assert avg_time_ms < 15, "Average time #{avg_time_ms}ms exceeds 15ms threshold with custom fields"
      end

      test "performance: time entry payload generation" do
        time_entry = TimeEntry.generate!(
          project: @project,
          issue: @issue,
          user: @user,
          hours: 2.5,
          spent_on: Date.today,
          activity: TimeEntryActivity.first || TimeEntryActivity.generate!(name: "Development")
        )

        event_data = {
          event_type: "time_entry",
          action: "created",
          event_id: SecureRandom.uuid,
          sequence_number: generate_sequence_number,
          occurred_at: Time.now,
          resource: time_entry,
          project: @project,
          actor: resolve_actor,
          changes: { hours: [nil, 2.5] }
        }

        builder = PayloadBuilder.new(event_data, "minimal")

        time = Benchmark.realtime do
          100.times do
            builder.build
          end
        end

        avg_time_ms = (time * 1000) / 100
        assert avg_time_ms < 5, "Average time #{avg_time_ms}ms exceeds 5ms threshold for time entries"
      end

      test "performance: multiple consecutive builds are efficient" do
        builder = PayloadBuilder.new(@base_event_data, "full")

        time = Benchmark.realtime do
          500.times do
            builder.build
          end
        end

        avg_time_us = (time * 1_000_000) / 500
        assert avg_time_us < 8000, "Average time #{avg_time_us}μs exceeds 8000μs threshold for consecutive builds"
      end

      private

      def generate_event_id
        SecureRandom.uuid
      end

      def generate_sequence_number
        (Time.now.to_f * 1_000_000).to_i
      end

      def resolve_actor
        user = User.current
        return nil if user.nil? || user.anonymous?
        { id: user.id, login: user.login, name: user.name }
      end
    end
  end
end
