module RedmineWebhookPlugin
  module EventHelpers
    module ActorResolver
      def resolve_actor
        user = Thread.current[:redmine_webhook_user] || User.current
        return nil if user.nil? || user.anonymous?

        { id: user.id, login: user.login, name: user.name }
      end
    end
  end
end
