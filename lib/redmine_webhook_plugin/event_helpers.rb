require_relative "event_helpers/actor_resolver"
require_relative "event_helpers/event_id_generator"
require_relative "event_helpers/sequence_number_generator"

module RedmineWebhookPlugin
  module EventHelpers
    include ActorResolver
    include EventIdGenerator
    include SequenceNumberGenerator
  end
end
