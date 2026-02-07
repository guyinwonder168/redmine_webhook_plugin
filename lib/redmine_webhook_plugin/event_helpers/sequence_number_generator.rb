module RedmineWebhookPlugin
  module EventHelpers
    module SequenceNumberGenerator
      def generate_sequence_number
        (Time.now.to_f * 1_000_000).to_i
      end
    end
  end
end
