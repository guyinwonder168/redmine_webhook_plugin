require_relative "lib/redmine_webhook_plugin"
require_relative "lib/redmine_webhook_plugin/hooks"
require_relative "lib/redmine_webhook_plugin/patches"

Rails.application.config.to_prepare do
  require_dependency File.expand_path("../app/services/webhook/payload_builder", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/delivery_result", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/error_classifier", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/retry_policy", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/api_key_resolver", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/headers_builder", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/http_client", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/dispatcher", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/execution_mode", __FILE__)
  require_dependency File.expand_path("../app/services/webhook/sender", __FILE__)
  require_dependency File.expand_path("../app/jobs/webhook/delivery_job", __FILE__)
  require_dependency File.expand_path("../app/models/redmine_webhook_plugin/webhook/endpoint", __FILE__)
  require_dependency File.expand_path("../app/models/redmine_webhook_plugin/webhook/delivery", __FILE__)
  RedmineWebhookPlugin.disable_native_webhooks!
  RedmineWebhookPlugin::Patches.load
end

Redmine::Plugin.register :redmine_webhook_plugin do
  name "Redmine Webhook Plugin"
  author "Redmine Webhook Plugin Contributors"
  description "Outbound webhooks for issues and time entries"
  version "1.0.0-RC"
  requires_redmine version_or_higher: "5.1.0"

  menu :admin_menu, :webhooks, { controller: "admin/webhook_endpoints", action: "index" },
       caption: :label_webhook_endpoints, html: { class: "icon icon-webhook" },
       after: :roles
   menu :admin_menu, :webhook_deliveries, { controller: "admin/webhook_deliveries", action: "index" },
       caption: :label_webhook_deliveries, html: { class: "icon icon-webhook-deliveries" },
       after: :webhooks

   settings partial: "settings/webhook_settings", default: {
    "execution_mode" => "auto",
    "retention_days_success" => "7",
    "retention_days_failed" => "7",
    "deliveries_paused" => "0"
  }
end
