require File.expand_path("../test_helper", __dir__)

class SettingsTest < ActiveSupport::TestCase
  test "plugin settings include execution and retention" do
    settings = Setting.plugin_redmine_webhook_plugin
    assert settings.key?("execution_mode")
    assert settings.key?("retention_days_success")
    assert settings.key?("retention_days_failed")
  end

  test "plugin settings default values" do
    settings = Setting.plugin_redmine_webhook_plugin
    assert_equal "auto", settings["execution_mode"]
    assert_equal "7", settings["retention_days_success"]
    assert_equal "7", settings["retention_days_failed"]
    assert_equal "0", settings["deliveries_paused"]
  end
end
