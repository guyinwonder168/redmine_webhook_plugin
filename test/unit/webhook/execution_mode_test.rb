require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::ExecutionModeTest < ActiveSupport::TestCase
  def setup
    super
    @original_adapter = ActiveJob::Base.queue_adapter
    @settings_supported = Setting.respond_to?(:plugin_redmine_webhook_plugin)
    @defined_setting_accessors = false

    unless @settings_supported
      Setting.singleton_class.class_eval do
        attr_accessor :plugin_redmine_webhook_plugin
      end
      @defined_setting_accessors = true
    end

    @original_settings = Setting.plugin_redmine_webhook_plugin
  end

  def teardown
    Setting.plugin_redmine_webhook_plugin = @original_settings
    ActiveJob::Base.queue_adapter = @original_adapter
    if @defined_setting_accessors
      Setting.singleton_class.class_eval do
        remove_method :plugin_redmine_webhook_plugin
        remove_method :plugin_redmine_webhook_plugin=
      end
    end
    super
  end

  test "detect returns :activejob when queue adapter present" do
    ActiveJob::Base.queue_adapter = :async
    Setting.plugin_redmine_webhook_plugin = {}

    assert_equal :activejob, RedmineWebhookPlugin::Webhook::ExecutionMode.detect
  end

  test "detect returns :db_runner when no queue adapter" do
    ActiveJob::Base.queue_adapter = :inline
    Setting.plugin_redmine_webhook_plugin = {}

    assert_equal :db_runner, RedmineWebhookPlugin::Webhook::ExecutionMode.detect
  end

  test "detect uses override setting" do
    ActiveJob::Base.queue_adapter = :async
    Setting.plugin_redmine_webhook_plugin = { "execution_mode" => "db_runner" }

    assert_equal :db_runner, RedmineWebhookPlugin::Webhook::ExecutionMode.detect
  end
end
