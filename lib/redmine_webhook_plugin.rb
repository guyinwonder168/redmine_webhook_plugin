module RedmineWebhookPlugin
  PLUGIN_ID = "redmine_webhook_plugin"

  module NativeWebhookDisable
    def enabled?
      false
    end
  end

  def self.native_webhooks_available?
    return false unless defined?(::Webhook)
    return false unless defined?(::ActiveRecord::Base)

    ::Webhook < ::ActiveRecord::Base
  end

  def self.disable_native_webhooks!
    unless defined?(::Webhook)
      begin
        require_dependency "webhook"
      rescue LoadError, NameError
        return
      end
    end

    return unless native_webhooks_available?

    singleton = ::Webhook.singleton_class
    return if singleton.ancestors.include?(NativeWebhookDisable)

    singleton.prepend(NativeWebhookDisable)
  end
end

