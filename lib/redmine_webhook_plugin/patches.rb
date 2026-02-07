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
