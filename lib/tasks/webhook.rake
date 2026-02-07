namespace :redmine do
  namespace :webhooks do
    desc "Process pending webhook deliveries"
    task :process => :environment do
      batch_size = (ENV['BATCH_SIZE'] || 50).to_i
      deliveries = RedmineWebhookPlugin::Webhook::Delivery
        .where(status: [
          RedmineWebhookPlugin::Webhook::Delivery::PENDING,
          RedmineWebhookPlugin::Webhook::Delivery::FAILED
        ])
        .due
        .limit(batch_size)

      deliveries.each do |delivery|
        RedmineWebhookPlugin::Webhook::Sender.send(delivery)
      end
    end

    desc "Purge old webhook delivery logs based on retention policy"
    task :purge => :environment do
      retention_success = (ENV["RETENTION_DAYS_SUCCESS"] || 7).to_i
      retention_failed = (ENV["RETENTION_DAYS_FAILED"] || 7).to_i

      success_cutoff = retention_success.days.ago
      failed_cutoff = retention_failed.days.ago

      success_count = RedmineWebhookPlugin::Webhook::Delivery
        .where(status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS)
        .where("delivered_at < ?", success_cutoff)
        .delete_all

      failed_count = RedmineWebhookPlugin::Webhook::Delivery
        .where(status: [
          RedmineWebhookPlugin::Webhook::Delivery::FAILED,
          RedmineWebhookPlugin::Webhook::Delivery::DEAD
        ])
        .where("delivered_at < ?", failed_cutoff)
        .delete_all

      total = success_count + failed_count
      puts "Purged #{total} deliveries (#{success_count} successful, #{failed_count} failed/dead)"
    end
  end
end
