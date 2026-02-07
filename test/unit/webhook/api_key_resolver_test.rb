require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::ApiKeyResolverTest < ActiveSupport::TestCase
  fixtures :users

  test "resolve returns token value for user object" do
    user = User.find(1)
    token = create_api_token(user)

    assert_equal token.value, RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(user)
  end

  test "resolve returns token value for user id" do
    user = User.find(1)
    token = create_api_token(user)

    assert_equal token.value, RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(user.id)
  end

  test "resolve returns nil when user has no token" do
    user = User.find(1)
    clear_api_tokens(user)

    assert_nil RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(user)
  end

  test "resolve returns nil when user id is unknown" do
    assert_nil RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(999_999)
  end

  test "resolve returns nil when user is nil" do
    assert_nil RedmineWebhookPlugin::Webhook::ApiKeyResolver.resolve(nil)
  end

  test "generate_if_missing returns existing token when present" do
    user = User.find(1)
    token = create_api_token(user)
    Setting.stubs(:rest_api_enabled?).returns(true)

    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(user)

    assert_equal token.value, result
    assert_equal 1, Token.where(user_id: user.id, action: "api").count
  end

  test "generate_if_missing creates token when missing" do
    user = User.find(1)
    clear_api_tokens(user)
    Setting.stubs(:rest_api_enabled?).returns(true)

    result = RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(user)

    assert_equal 1, Token.where(user_id: user.id, action: "api").count
    assert_equal Token.find_by(user_id: user.id, action: "api").value, result
  end

  test "generate_if_missing raises RestApiDisabledError when rest api is disabled" do
    user = User.find(1)
    Setting.stubs(:rest_api_enabled?).returns(false)

    assert_raises(RedmineWebhookPlugin::Webhook::ApiKeyResolver::RestApiDisabledError) do
      RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(user)
    end
  end

  test "generate_if_missing raises UserNotFoundError when user is invalid" do
    Setting.stubs(:rest_api_enabled?).returns(true)

    assert_raises(RedmineWebhookPlugin::Webhook::ApiKeyResolver::UserNotFoundError) do
      RedmineWebhookPlugin::Webhook::ApiKeyResolver.generate_if_missing(999_999)
    end
  end

  test "fingerprint returns missing for nil" do
    assert_equal "missing", RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(nil)
  end

  test "fingerprint returns missing for empty string" do
    assert_equal "missing", RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint("")
  end

  test "fingerprint returns sha256 hex digest" do
    expected = "3c469e9d6c5875d37a43f353d4f88e61fcf812c66eee3457465a40b0da4153e0"

    assert_equal expected, RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint("token")
  end

  test "fingerprint is consistent for the same key" do
    key = "api-token"

    assert_equal RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(key),
                 RedmineWebhookPlugin::Webhook::ApiKeyResolver.fingerprint(key)
  end

  private

  def clear_api_tokens(user)
    Token.where(user_id: user.id, action: "api").delete_all
  end

  def create_api_token(user)
    clear_api_tokens(user)
    Token.create!(user: user, action: "api")
  end
end
