# Workstream B: Event Capture Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Capture Issue and TimeEntry lifecycle events and dispatch structured event data for downstream delivery.

**Architecture:** Add Issue/TimeEntry model patches with lifecycle hooks, change/snapshot capture, and a dispatcher integration point. Provide helper utilities for event ids, sequence numbers, and actor normalization, plus a patch loader wired in `init.rb`.

**Tech Stack:** Ruby, Rails/ActiveRecord callbacks, Redmine plugin API, Minitest

**Depends on:** P0 complete

## Native Webhook Compatibility

Redmine 7.0+ (trunk) has native webhook support. The plugin remains authoritative; when native webhooks exist, disable or bypass native delivery so plugin patches remain active and events are emitted consistently.

- **Namespace**: Use `RedmineWebhookPlugin::` for all code to avoid conflicts with native `Webhook` class
- **Detection**: Check `defined?(::Webhook) && ::Webhook < ActiveRecord::Base` at runtime (avoid `ApplicationRecord` on 5.1.x)
- **Redmine 5.1.x / 6.1.x**: Apply full event capture patches
- **Redmine 7.0+**: Apply plugin patches and disable native webhook delivery to avoid duplicate events

**Native webhook events** (as of trunk): Issue created/updated/deleted (disabled when plugin is active)
**Plugin-only events**: TimeEntry created/updated/deleted (not in native)

---

## Testing Environment (Podman)

All tests run inside Podman containers to ensure consistent Ruby/Rails versions. The workspace has three Redmine versions available:

| Version | Directory | Image | Ruby |
|---------|-----------|-------|------|
| 5.1.0 | `.redmine-test/redmine-5.1.0/` | `redmine-dev:5.1.0` | 3.2.2 |
| 5.1.10 | `.redmine-test/redmine-5.1.10/` | `redmine-dev:5.1.10` | 3.2.2 |
| 6.1.0 | `.redmine-test/redmine-6.1.0/` | `redmine-dev:6.1.0` | 3.3.4 |
| 7.0.0-dev | `.redmine-test/redmine-7.0.0-dev/` | `redmine-dev:7.0.0-dev` | 3.3.4 |

> **IMPORTANT:** Every task MUST be verified on ALL FOUR Redmine versions before marking complete.

### Cross-Version Test Pattern

After implementing each task, run the test on all three versions:

```bash
# From /media/eddy/hdd/Project/redmine_webhook_plugin

# 5.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 7.0.0-dev
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-7.0.0-dev:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/7.0.0-dev:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:7.0.0-dev \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'
```

---

## Task 1: Issue Patch Setup

**Files:**
- Create: `lib/redmine_webhook_plugin/patches/issue_patch.rb`
- Test: `test/unit/issue_patch_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/issue_patch_test.rb
require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches/issue_patch", __dir__)

class IssuePatchTest < ActiveSupport::TestCase
  setup do
    Issue.send(:include, RedmineWebhookPlugin::Patches::IssuePatch) unless
      Issue.included_modules.include?(RedmineWebhookPlugin::Patches::IssuePatch)
  end

  test "registers issue lifecycle callbacks" do
    commit_filters = Issue._commit_callbacks.map(&:filter)
    assert_includes commit_filters, :webhook_after_create
    assert_includes commit_filters, :webhook_after_update
    assert_includes commit_filters, :webhook_after_destroy

    destroy_filters = Issue._destroy_callbacks.map(&:filter)
    assert_includes destroy_filters, :webhook_capture_for_delete
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```


Expected: FAIL with missing callbacks or uninitialized constant

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/patches/issue_patch.rb
require "active_support/concern"

module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_after_create
      end

      def webhook_after_update
      end

      def webhook_capture_for_delete
      end

      def webhook_after_destroy
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/patches/issue_patch.rb test/unit/issue_patch_test.rb
git commit -m "feat(ws-b): add Issue patch with lifecycle callbacks"
```

---

## Task 2: Issue Change Capture

**Files:**
- Modify: `lib/redmine_webhook_plugin/patches/issue_patch.rb`
- Modify: `test/unit/issue_patch_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/issue_patch_test.rb - add to existing file
class IssuePatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :issues

  test "captures changes and actor on update" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user

    issue.subject = "Webhook subject update"
    issue.save!

    changes = issue.instance_variable_get(:@webhook_changes)
    actor = issue.instance_variable_get(:@webhook_actor)

    assert changes.key?("subject")
    assert_equal "Webhook subject update", changes["subject"].last
    assert_equal user, actor
  end

  test "captures snapshot and actor on destroy" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user
    issue_id = issue.id

    issue.destroy

    snapshot = issue.instance_variable_get(:@webhook_snapshot)
    actor = issue.instance_variable_get(:@webhook_actor)

    assert_equal issue_id, snapshot["id"]
    assert_equal user, actor
  end

  test "captures journal on update" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user

    issue.init_journal(user, "Adding a note to the issue")
    issue.subject = "Updated with journal"
    issue.save!

    journal = issue.instance_variable_get(:@webhook_journal)

    assert_not_nil journal
    assert_equal "Adding a note to the issue", journal.notes
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```


Expected: FAIL with `@webhook_changes`, `@webhook_snapshot`, or `@webhook_journal` missing

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/patches/issue_patch.rb
module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = User.current
        @webhook_journal = @current_journal
      end

      def webhook_after_create
      end

      def webhook_after_update
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = User.current
      end

      def webhook_after_destroy
      end
    end
  end
end
```

**Note:** Capturing `@current_journal` enables full context in issue update events. The journal contains user notes, detailed change tracking, and rich metadata about what changed during an issue update. This journal data is passed to the dispatcher and eventually serialized in the payload for downstream consumers.

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/patches/issue_patch.rb test/unit/issue_patch_test.rb
git commit -m "feat(ws-b): capture Issue changes and delete snapshots"
```

---

## Task 3: Issue Event Methods

**Files:**
- Modify: `lib/redmine_webhook_plugin/patches/issue_patch.rb`
- Modify: `test/unit/issue_patch_test.rb`

**Note:** Journal data captured in Task 2's `webhook_capture_changes` is now available in event dispatching. The `@webhook_journal` instance variable contains the journal record (with id, notes, created_on) for "updated" actions, enabling full context in issue update events. This journal data will be included in the payload by the PayloadBuilder in Workstream C.

**Step 1: Write the failing tests**

```ruby
# test/unit/issue_patch_test.rb - add to existing file
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    class << self
      attr_accessor :last_event
    end

    def self.dispatch(event_data)
      self.last_event = event_data
    end
  end
end

class IssuePatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :issues

  test "dispatches created issue event" do
    user = User.find(1)
    project = Project.find(1)
    tracker = Tracker.find(1)
    status = IssueStatus.find(1)
    User.current = user

    issue = Issue.new(
      project: project,
      tracker: tracker,
      status: status,
      author: user,
      subject: "Webhook create"
    )

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    issue.save!

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "issue", event[:event_type]
    assert_equal "created", event[:action]
    assert_equal issue.id, event[:resource][:id]
  end

  test "dispatches updated issue event with changes" do
    issue = Issue.find(1)
    User.current = User.find(1)

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    issue.subject = "Webhook update"
    issue.save!

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "updated", event[:action]
    assert event[:changes].key?("subject")
  end

  test "dispatches updated issue event with journal" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    issue.init_journal(user, "Adding a note")
    issue.subject = "Updated with journal"
    issue.save!

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "updated", event[:action]
    assert_not_nil event[:journal]
    assert_equal "Adding a note", event[:journal].notes
  end

  test "dispatches deleted issue event with snapshot" do
    issue = Issue.find(1)
    User.current = User.find(1)
    issue_id = issue.id

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    issue.destroy

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "deleted", event[:action]
    assert_equal issue_id, event[:resource][:id]
    assert_equal issue_id, event[:changes]["id"]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```


Expected: FAIL with `dispatch` not called

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/patches/issue_patch.rb
module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = User.current
        @webhook_journal = @current_journal
      end

      def webhook_after_create
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
      end

      def webhook_after_update
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = User.current
      end

      def webhook_after_destroy
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
      end

      def webhook_event_data(action, changes, source)
        {
          event_type: "issue",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: nil,
          sequence_number: nil
        }
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          { type: "issue", id: source["id"], project_id: source["project_id"] }
        else
          { type: "issue", id: source.id, project_id: source.project_id }
        end
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/issue_patch_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 7 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/patches/issue_patch.rb test/unit/issue_patch_test.rb
git commit -m "feat(ws-b): dispatch Issue events with basic event data"
```

---

## Task 4: TimeEntry Patch Setup

**Files:**
- Create: `lib/redmine_webhook_plugin/patches/time_entry_patch.rb`
- Test: `test/unit/time_entry_patch_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/time_entry_patch_test.rb
require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches/time_entry_patch", __dir__)

class TimeEntryPatchTest < ActiveSupport::TestCase
  setup do
    TimeEntry.send(:include, RedmineWebhookPlugin::Patches::TimeEntryPatch) unless
      TimeEntry.included_modules.include?(RedmineWebhookPlugin::Patches::TimeEntryPatch)
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
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'
```


Expected: FAIL with missing callbacks or uninitialized constant

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/patches/time_entry_patch.rb
require "active_support/concern"

module RedmineWebhookPlugin
  module Patches
    module TimeEntryPatch
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = User.current
      end

      def webhook_after_create
      end

      def webhook_after_update
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = User.current
      end

      def webhook_after_destroy
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/patches/time_entry_patch.rb test/unit/time_entry_patch_test.rb
git commit -m "feat(ws-b): add TimeEntry patch with lifecycle callbacks"
```

---

## Task 5: TimeEntry Event Methods

**Files:**
- Modify: `lib/redmine_webhook_plugin/patches/time_entry_patch.rb`
- Modify: `test/unit/time_entry_patch_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/time_entry_patch_test.rb - add to existing file
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    class << self
      attr_accessor :last_event
    end

    def self.dispatch(event_data)
      self.last_event = event_data
    end
  end
end

class TimeEntryPatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :time_entries, :enumerations

  test "dispatches created time entry event" do
    user = User.find(1)
    project = Project.find(1)
    issue = Issue.find(1)
    activity = TimeEntryActivity.first
    User.current = user

    entry = TimeEntry.new(
      project: project,
      issue: issue,
      user: user,
      activity: activity,
      hours: 1.5,
      spent_on: Date.today
    )

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    entry.save!

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "time_entry", event[:event_type]
    assert_equal "created", event[:action]
    assert_equal entry.id, event[:resource][:id]
    assert_equal issue.id, event[:resource][:issue_id]
    assert_equal project.id, event[:resource][:project_id]
  end

  test "dispatches updated time entry event with changes" do
    entry = TimeEntry.find(1)
    User.current = User.find(1)

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    entry.hours = entry.hours + 1.0
    entry.save!

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "updated", event[:action]
    assert event[:changes].key?("hours")
  end

  test "dispatches deleted time entry event with snapshot" do
    entry = TimeEntry.find(1)
    User.current = User.find(1)
    entry_id = entry.id

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    entry.destroy

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "deleted", event[:action]
    assert_equal entry_id, event[:resource][:id]
    assert_equal entry_id, event[:changes]["id"]
  end

  test "handles nil issue on create" do
    user = User.find(1)
    project = Project.find(1)
    activity = TimeEntryActivity.first
    User.current = user

    entry = TimeEntry.new(
      project: project,
      issue: nil,
      user: user,
      activity: activity,
      hours: 0.5,
      spent_on: Date.today
    )

    RedmineWebhookPlugin::Webhook::Dispatcher.last_event = nil
    entry.save!

    event = RedmineWebhookPlugin::Webhook::Dispatcher.last_event
    assert_equal "created", event[:action]
    assert_nil event[:resource][:issue_id]
    assert_equal project.id, event[:resource][:project_id]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'
```


Expected: FAIL with `dispatch` not called

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/patches/time_entry_patch.rb
module RedmineWebhookPlugin
  module Patches
    module TimeEntryPatch
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = User.current
      end

      def webhook_after_create
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
      end

      def webhook_after_update
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = User.current
      end

      def webhook_after_destroy
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
      end

      def webhook_event_data(action, changes, source)
        {
          event_type: "time_entry",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: nil,
          sequence_number: nil
        }
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          {
            type: "time_entry",
            id: source["id"],
            issue_id: source["issue_id"],
            project_id: source["project_id"]
          }
        else
          {
            type: "time_entry",
            id: source.id,
            issue_id: source.issue_id,
            project_id: source.project_id
          }
        end
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/time_entry_patch_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/patches/time_entry_patch.rb test/unit/time_entry_patch_test.rb
git commit -m "feat(ws-b): dispatch TimeEntry events with basic event data"
```

---

## Task 6: Patch Loading

**Files:**
- Create: `lib/redmine_webhook_plugin/patches.rb`
- Modify: `init.rb`
- Test: `test/unit/patches_loader_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/patches_loader_test.rb
require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches", __dir__)

class PatchesLoaderTest < ActiveSupport::TestCase
  test "loads issue and time entry patches" do
    RedmineWebhookPlugin::Patches.load

    assert Issue.included_modules.include?(RedmineWebhookPlugin::Patches::IssuePatch)
    assert TimeEntry.included_modules.include?(RedmineWebhookPlugin::Patches::TimeEntryPatch)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/patches_loader_test.rb -v'
```


Expected: FAIL with missing `Patches.load`

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/patches.rb
module RedmineWebhookPlugin
  module Patches
    def self.load
      require_dependency File.expand_path("patches/issue_patch", __dir__)
      require_dependency File.expand_path("patches/time_entry_patch", __dir__)

      Issue.include(RedmineWebhookPlugin::Patches::IssuePatch) unless
        Issue.included_modules.include?(RedmineWebhookPlugin::Patches::IssuePatch)

      TimeEntry.include(RedmineWebhookPlugin::Patches::TimeEntryPatch) unless
        TimeEntry.included_modules.include?(RedmineWebhookPlugin::Patches::TimeEntryPatch)
    end
  end
end
```

```ruby
# init.rb
require_relative "lib/redmine_webhook_plugin"
require_relative "lib/redmine_webhook_plugin/patches"

Rails.application.config.to_prepare do
  RedmineWebhookPlugin::Patches.load
end

Redmine::Plugin.register :redmine_webhook_plugin do
  name "Redmine Webhook Plugin"
  author "Redmine Webhook Plugin Contributors"
  description "Outbound webhooks for issues and time entries (internal)"
  version "0.0.1"
  requires_redmine version_or_higher: "5.1.1"
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/patches_loader_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/patches_loader_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/patches_loader_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/patches.rb init.rb test/unit/patches_loader_test.rb
git commit -m "feat(ws-b): load Issue and TimeEntry patches on init"
```

---

## Task 7: Sequence Number Generation

**Files:**
- Create: `lib/redmine_webhook_plugin/event_helpers.rb`
- Test: `test/unit/event_helpers_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/event_helpers_test.rb
require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/event_helpers", __dir__)

class EventHelpersTest < ActiveSupport::TestCase
  Dummy = Class.new do
    include RedmineWebhookPlugin::EventHelpers
  end

  test "generate_sequence_number returns integer microseconds" do
    helper = Dummy.new
    first = helper.generate_sequence_number
    second = helper.generate_sequence_number

    assert_kind_of Integer, first
    assert second >= first
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```


Expected: FAIL with `generate_sequence_number` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/event_helpers.rb
module RedmineWebhookPlugin
  module EventHelpers
    def generate_sequence_number
      (Time.now.to_f * 1_000_000).to_i
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/event_helpers.rb test/unit/event_helpers_test.rb
git commit -m "feat(ws-b): add sequence number helper"
```

---

## Task 8: Actor Resolution

**Files:**
- Modify: `lib/redmine_webhook_plugin/event_helpers.rb`
- Modify: `lib/redmine_webhook_plugin/patches/issue_patch.rb`
- Modify: `lib/redmine_webhook_plugin/patches/time_entry_patch.rb`
- Modify: `test/unit/event_helpers_test.rb`
- Modify: `test/unit/issue_patch_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/event_helpers_test.rb - add to existing file
class EventHelpersTest < ActiveSupport::TestCase
  Dummy = Class.new do
    include RedmineWebhookPlugin::EventHelpers
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
end
```

```ruby
# test/unit/issue_patch_test.rb - update existing tests
class IssuePatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :issues

  test "captures changes and actor on update" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user

    issue.subject = "Webhook subject update"
    issue.save!

    changes = issue.instance_variable_get(:@webhook_changes)
    actor = issue.instance_variable_get(:@webhook_actor)

    assert changes.key?("subject")
    assert_equal "Webhook subject update", changes["subject"].last
    assert_equal({ id: user.id, login: user.login, name: user.name }, actor)
  end

  test "captures snapshot and actor on destroy" do
    issue = Issue.find(1)
    user = User.find(1)
    User.current = user
    issue_id = issue.id

    issue.destroy

    snapshot = issue.instance_variable_get(:@webhook_snapshot)
    actor = issue.instance_variable_get(:@webhook_actor)

    assert_equal issue_id, snapshot["id"]
    assert_equal({ id: user.id, login: user.login, name: user.name }, actor)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```


Expected: FAIL with `resolve_actor` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/event_helpers.rb
module RedmineWebhookPlugin
  module EventHelpers
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
```

```ruby
# lib/redmine_webhook_plugin/patches/issue_patch.rb
require_relative "../event_helpers"

module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      include RedmineWebhookPlugin::EventHelpers
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = resolve_actor
      end

      def webhook_after_create
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
      end

      def webhook_after_update
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = resolve_actor
      end

      def webhook_after_destroy
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
      end

      def webhook_event_data(action, changes, source)
        {
          event_type: "issue",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: nil,
          sequence_number: nil
        }
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          { type: "issue", id: source["id"], project_id: source["project_id"] }
        else
          { type: "issue", id: source.id, project_id: source.project_id }
        end
      end
    end
  end
end
```

```ruby
# lib/redmine_webhook_plugin/patches/time_entry_patch.rb
require_relative "../event_helpers"

module RedmineWebhookPlugin
  module Patches
    module TimeEntryPatch
      include RedmineWebhookPlugin::EventHelpers
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = resolve_actor
      end

      def webhook_after_create
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
      end

      def webhook_after_update
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = resolve_actor
      end

      def webhook_after_destroy
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
      end

      def webhook_event_data(action, changes, source)
        {
          event_type: "time_entry",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: nil,
          sequence_number: nil
        }
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          {
            type: "time_entry",
            id: source["id"],
            issue_id: source["issue_id"],
            project_id: source["project_id"]
          }
        else
          {
            type: "time_entry",
            id: source.id,
            issue_id: source.issue_id,
            project_id: source.project_id
          }
        end
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/event_helpers.rb lib/redmine_webhook_plugin/patches/issue_patch.rb lib/redmine_webhook_plugin/patches/time_entry_patch.rb test/unit/event_helpers_test.rb test/unit/issue_patch_test.rb
git commit -m "feat(ws-b): add actor resolution helper and use in patches"
```

---

## Task 9: Event ID Generation

**Files:**
- Modify: `lib/redmine_webhook_plugin/event_helpers.rb`
- Modify: `test/unit/event_helpers_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/event_helpers_test.rb - add to existing file
class EventHelpersTest < ActiveSupport::TestCase
  Dummy = Class.new do
    include RedmineWebhookPlugin::EventHelpers
  end

  test "generate_event_id returns UUID" do
    helper = Dummy.new
    event_id = helper.generate_event_id

    assert_equal 36, event_id.length
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i, event_id)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```


Expected: FAIL with `generate_event_id` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/redmine_webhook_plugin/event_helpers.rb
require "securerandom"

module RedmineWebhookPlugin
  module EventHelpers
    def generate_sequence_number
      (Time.now.to_f * 1_000_000).to_i
    end

    def resolve_actor
      user = User.current
      return nil if user.nil? || user.anonymous?

      { id: user.id, login: user.login, name: user.name }
    end

    def generate_event_id
      SecureRandom.uuid
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/event_helpers_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/redmine_webhook_plugin/event_helpers.rb test/unit/event_helpers_test.rb
git commit -m "feat(ws-b): add event id helper"
```

---

## Task 10: Dispatcher Interface and Full Event Data

**Files:**
- Create: `app/services/webhook/dispatcher.rb`
- Modify: `lib/redmine_webhook_plugin/patches/issue_patch.rb`
- Modify: `lib/redmine_webhook_plugin/patches/time_entry_patch.rb`
- Modify: `test/unit/issue_patch_test.rb`
- Modify: `test/unit/time_entry_patch_test.rb`
- Test: `test/unit/dispatcher_interface_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/dispatcher_interface_test.rb
require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../app/services/webhook/dispatcher", __dir__)

class DispatcherInterfaceTest < ActiveSupport::TestCase
  test "dispatcher exposes dispatch interface" do
    assert_respond_to RedmineWebhookPlugin::Webhook::Dispatcher, :dispatch
  end
end
```

```ruby
# test/unit/issue_patch_test.rb - update existing tests
class IssuePatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :issue_statuses, :issues

  test "dispatches created issue event with ids" do
    user = User.find(1)
    project = Project.find(1)
    tracker = Tracker.find(1)
    status = IssueStatus.find(1)
    User.current = user

    issue = Issue.new(
      project: project,
      tracker: tracker,
      status: status,
      author: user,
      subject: "Webhook create"
    )

    captured = nil
    RedmineWebhookPlugin::Webhook::Dispatcher.stub(:dispatch, ->(event) { captured = event }) do
      issue.save!
    end

    assert_equal "issue", captured[:event_type]
    assert_equal "created", captured[:action]
    assert_equal issue.id, captured[:resource][:id]
    assert_equal 36, captured[:event_id].length
    assert_kind_of Integer, captured[:sequence_number]
  end
end
```

```ruby
# test/unit/time_entry_patch_test.rb - update existing tests
class TimeEntryPatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :time_entries, :enumerations

  test "dispatches created time entry event with ids" do
    user = User.find(1)
    project = Project.find(1)
    issue = Issue.find(1)
    activity = TimeEntryActivity.first
    User.current = user

    entry = TimeEntry.new(
      project: project,
      issue: issue,
      user: user,
      activity: activity,
      hours: 1.5,
      spent_on: Date.today
    )

    captured = nil
    RedmineWebhookPlugin::Webhook::Dispatcher.stub(:dispatch, ->(event) { captured = event }) do
      entry.save!
    end

    assert_equal "time_entry", captured[:event_type]
    assert_equal "created", captured[:action]
    assert_equal entry.id, captured[:resource][:id]
    assert_equal 36, captured[:event_id].length
    assert_kind_of Integer, captured[:sequence_number]
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/dispatcher_interface_test.rb -v'
```


Expected: FAIL with missing dispatcher file or missing event_id/sequence_number

**Step 3: Write minimal implementation**

```ruby
# app/services/webhook/dispatcher.rb
module RedmineWebhookPlugin::Webhook
  class Dispatcher
    def self.dispatch(_event_data)
      # Interface placeholder; real implementation in integration phase.
    end
  end
end
```

```ruby
# lib/redmine_webhook_plugin/patches/issue_patch.rb
require_relative "../event_helpers"

module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      include RedmineWebhookPlugin::EventHelpers
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = resolve_actor
      end

      def webhook_after_create
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
      end

      def webhook_after_update
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = resolve_actor
      end

      def webhook_after_destroy
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
      end

      def webhook_event_data(action, changes, source)
        {
          event_type: "issue",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: generate_event_id,
          sequence_number: generate_sequence_number
        }
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          { type: "issue", id: source["id"], project_id: source["project_id"] }
        else
          { type: "issue", id: source.id, project_id: source.project_id }
        end
      end
    end
  end
end
```

```ruby
# lib/redmine_webhook_plugin/patches/time_entry_patch.rb
require_relative "../event_helpers"

module RedmineWebhookPlugin
  module Patches
    module TimeEntryPatch
      include RedmineWebhookPlugin::EventHelpers
      extend ActiveSupport::Concern

      included do
        before_save :webhook_capture_changes
        after_commit :webhook_after_create, on: :create
        after_commit :webhook_after_update, on: :update
        before_destroy :webhook_capture_for_delete
        after_commit :webhook_after_destroy, on: :destroy
      end

      private

      def webhook_capture_changes
        @webhook_changes = changes_to_save
        @webhook_actor = resolve_actor
      end

      def webhook_after_create
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("created", @webhook_changes, self))
      end

      def webhook_after_update
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("updated", @webhook_changes, self))
      end

      def webhook_capture_for_delete
        @webhook_snapshot = attributes.dup
        @webhook_actor = resolve_actor
      end

      def webhook_after_destroy
        return if @webhook_skip

        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(webhook_event_data("deleted", @webhook_snapshot, @webhook_snapshot))
      end

      def webhook_event_data(action, changes, source)
        {
          event_type: "time_entry",
          action: action,
          resource: webhook_resource_hash(source),
          changes: changes,
          actor: @webhook_actor,
          event_id: generate_event_id,
          sequence_number: generate_sequence_number
        }
      end

      def webhook_resource_hash(source)
        if source.is_a?(Hash)
          {
            type: "time_entry",
            id: source["id"],
            issue_id: source["issue_id"],
            project_id: source["project_id"]
          }
        else
          {
            type: "time_entry",
            id: source.id,
            issue_id: source.issue_id,
            project_id: source.project_id
          }
        end
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/dispatcher_interface_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/dispatcher_interface_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/dispatcher_interface_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add app/services/webhook/dispatcher.rb lib/redmine_webhook_plugin/patches/issue_patch.rb lib/redmine_webhook_plugin/patches/time_entry_patch.rb test/unit/dispatcher_interface_test.rb test/unit/issue_patch_test.rb test/unit/time_entry_patch_test.rb
git commit -m "feat(ws-b): add dispatcher interface and full event identifiers"
---

## Task 15: Journal Integration

### Status: ✅ **COMPLETE**

### Summary
Added journal capture to Issue patch's `webhook_capture_changes` method:
- Captures `@current_journal` during issue save (contains user notes and detailed change tracking)
- Journal data is passed to dispatcher in `webhook_event_data` for "updated" events

### Implementation Details
- Modified: `lib/redmine_webhook_plugin/patches/issue_patch.rb`
  - Added `@webhook_journal = @current_journal` in `webhook_capture_changes`
  - Updated `webhook_event_data` to include journal for "updated" actions:
    ```ruby
    data[:journal] = @webhook_journal if action == "updated" && @webhook_journal
    ```
- Tests added in `test/unit/issue_patch_test.rb` to verify journal passing

**Related**: Task 15 (WS-C PayloadBuilder) - The PayloadBuilder serializes the journal data passed by Issue patch.

---

## Acceptance Criteria Checklist

- [ ] Creating an Issue triggers `webhook_after_create` and dispatch
- [ ] Updating an Issue captures changes in `@webhook_changes`
- [ ] Deleting an Issue captures a snapshot before destroy
- [ ] Same behavior works for TimeEntry, including nil issue
- [ ] Patches load without breaking Redmine
- [ ] Event data includes `event_id`, `sequence_number`, and actor hash
- [ ] All unit tests pass

---

## Execution Handoff

Plan complete and saved to `docs/plans/ws-b-event-capture.md`. Two execution options:

1. Subagent-Driven (this session) - dispatch a fresh subagent per task, review between tasks
2. Parallel Session (separate) - open new session with @superpowers:executing-plans