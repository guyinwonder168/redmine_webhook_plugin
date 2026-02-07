require File.expand_path("../test_helper", __dir__)

class WebhookModuleTest < ActiveSupport::TestCase
  test "Webhook module is defined" do
    assert defined?(RedmineWebhookPlugin::Webhook), "RedmineWebhookPlugin::Webhook should be defined"
    assert_kind_of Module, RedmineWebhookPlugin::Webhook
  end

  test "Webhook module has table_name_prefix" do
    assert_equal "webhook_", RedmineWebhookPlugin::Webhook.table_name_prefix
  end

  test "disable_native_webhooks overrides native enabled flag" do
    created = false

    begin
      if defined?(::Webhook)
        skip "native Webhook already defined"
      end

      webhook_class = Class.new(ActiveRecord::Base) do
        self.abstract_class = true

        def self.enabled?
          true
        end
      end

      Object.const_set(:Webhook, webhook_class)
      created = true

      RedmineWebhookPlugin.disable_native_webhooks!
      assert_equal false, ::Webhook.enabled?
    ensure
      Object.send(:remove_const, :Webhook) if created
    end
  end
end
