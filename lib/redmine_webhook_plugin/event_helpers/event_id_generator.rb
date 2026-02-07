require "securerandom"

module RedmineWebhookPlugin
  module EventHelpers
    module EventIdGenerator
      def generate_event_id
        SecureRandom.uuid
      end
    end
  end
end
