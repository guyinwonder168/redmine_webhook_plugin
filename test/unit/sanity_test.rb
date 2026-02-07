require File.expand_path("../test_helper", __dir__)

class SanityTest < ActiveSupport::TestCase
  test "plugin is registered" do
    assert Redmine::Plugin.find(RedmineWebhookPlugin::PLUGIN_ID)
  end
end
