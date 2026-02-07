require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::ErrorClassifierTest < ActiveSupport::TestCase
  test "classify returns connection_timeout for Timeout::Error" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(Timeout::Error.new)

    assert_equal "connection_timeout", result
  end

  test "classify returns read_timeout for Net::ReadTimeout" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(Net::ReadTimeout.new("read"))

    assert_equal "read_timeout", result
  end

  test "classify returns connection_timeout for Net::OpenTimeout" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(Net::OpenTimeout.new("open"))

    assert_equal "connection_timeout", result
  end

  test "classify returns connection_refused for Errno::ECONNREFUSED" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(Errno::ECONNREFUSED.new("refused"))

    assert_equal "connection_refused", result
  end

  test "classify returns connection_reset for Errno::ECONNRESET" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(Errno::ECONNRESET.new("reset"))

    assert_equal "connection_reset", result
  end

  test "classify returns dns_error for SocketError" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(SocketError.new("dns"))

    assert_equal "dns_error", result
  end

  test "classify returns ssl_error for OpenSSL::SSL::SSLError" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(OpenSSL::SSL::SSLError.new("ssl"))

    assert_equal "ssl_error", result
  end

  test "classify returns unknown_error for unknown exception" do
    result = RedmineWebhookPlugin::Webhook::ErrorClassifier.classify(StandardError.new("boom"))

    assert_equal "unknown_error", result
  end

  test "classify_http_status returns nil for 2xx" do
    assert_nil RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(200)
    assert_nil RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(204)
  end

  test "classify_http_status returns client_error for 4xx" do
    assert_equal "client_error", RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(400)
    assert_equal "client_error", RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(404)
  end

  test "classify_http_status returns server_error for 5xx" do
    assert_equal "server_error", RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(500)
    assert_equal "server_error", RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(503)
  end

  test "classify_http_status returns nil for nil" do
    assert_nil RedmineWebhookPlugin::Webhook::ErrorClassifier.classify_http_status(nil)
  end
end
