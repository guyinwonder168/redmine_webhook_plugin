require File.expand_path("../test_helper", __dir__)
require File.expand_path("../../lib/redmine_webhook_plugin/patches", __dir__)

class PatchesLoaderTest < ActiveSupport::TestCase
  test "loads issue and time entry patches" do
    RedmineWebhookPlugin::Patches.load

    assert Issue.included_modules.include?(RedmineWebhookPlugin::Patches::IssuePatch)
    assert TimeEntry.included_modules.include?(RedmineWebhookPlugin::Patches::TimeEntryPatch)
  end
end
