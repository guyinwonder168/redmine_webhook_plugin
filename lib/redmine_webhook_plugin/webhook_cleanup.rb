module RedmineWebhookPlugin
  module WebhookCleanup
    def cleanup_webhook_state
      remove_instance_variable(:@webhook_skip) if defined?(@webhook_skip)
      remove_instance_variable(:@webhook_changes) if defined?(@webhook_changes)
      remove_instance_variable(:@webhook_actor) if defined?(@webhook_actor)
      remove_instance_variable(:@webhook_journal) if defined?(@webhook_journal)
      remove_instance_variable(:@webhook_snapshot) if defined?(@webhook_snapshot)
      remove_instance_variable(:@current_journal) if defined?(@current_journal)
    end
  end
end
