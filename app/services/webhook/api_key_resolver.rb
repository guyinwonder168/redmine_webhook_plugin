module RedmineWebhookPlugin
  module Webhook
    class ApiKeyResolver
      API_ACTION = "api".freeze

      class RestApiDisabledError < StandardError; end
      class UserNotFoundError < StandardError; end

      def self.resolve(user_or_id)
        user = resolve_user(user_or_id)
        return nil unless user

        Token.find_by(user_id: user.id, action: API_ACTION)&.value
      end

      def self.generate_if_missing(user_or_id)
        user = resolve_user(user_or_id)
        raise UserNotFoundError, "user not found" unless user
        raise RestApiDisabledError, "rest api disabled" unless Setting.rest_api_enabled?

        token = Token.find_by(user_id: user.id, action: API_ACTION)
        return token.value if token

        Token.create!(user: user, action: API_ACTION).value
      end

      def self.fingerprint(api_key)
        return "missing" if api_key.nil?

        key = api_key.to_s
        return "missing" if key.empty?

        OpenSSL::Digest::SHA256.hexdigest(key)
      end

      def self.resolve_user(user_or_id)
        return user_or_id if user_or_id.is_a?(User)
        return nil if user_or_id.nil?

        User.find_by(id: user_or_id)
      end

      private_class_method :resolve_user
    end
  end
end
