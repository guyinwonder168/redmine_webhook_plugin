require "uri"
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::HttpClientTest < ActiveSupport::TestCase
  def setup
    @url = "https://example.test/webhook"
    @payload = "{\"event\":\"created\"}"
    @headers = { "Content-Type" => "application/json" }
  end

  test "initialize stores timeout and ssl_verify" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 15, ssl_verify: false)

    assert_equal 15, client.timeout
    assert_equal false, client.ssl_verify
  end

  test "post returns success result for 2xx response" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    response = build_response("204", "ok")
    http = build_http(response)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal true, result.success?
    assert_equal 204, result.http_status
    assert_equal "ok", result.response_body
    assert_equal @url, result.final_url
  end

  test "post returns failure result for 5xx response" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    response = build_response("500", "boom")
    http = build_http(response)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal false, result.success?
    assert_equal 500, result.http_status
    assert_equal "server_error", result.error_code
  end

  test "post applies configured timeouts" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 12, ssl_verify: true)
    response = build_response("200", "ok")
    http = build_http(response)
    http.expects(:open_timeout=).with(12)
    http.expects(:read_timeout=).with(12)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)

    client.post(url: @url, payload: @payload, headers: @headers)
  end

  test "post disables ssl verification when ssl_verify is false" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: false)
    response = build_response("200", "ok")
    http = build_http(response)
    http.expects(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)

    client.post(url: @url, payload: @payload, headers: @headers)
  end

  test "post records duration using monotonic clock" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    response = build_response("200", "ok")
    http = build_http(response)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)
    Process.stubs(:clock_gettime).returns(1.0, 1.234)

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal 234, result.duration_ms
  end

  test "post enables ssl verification when ssl_verify is true" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    response = build_response("200", "ok")
    http = build_http(response)
    http.expects(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)

    client.post(url: @url, payload: @payload, headers: @headers)
  end

  test "post returns failure for timeout errors" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)

    [Timeout::Error.new, Net::OpenTimeout.new].each do |exception|
      result = run_exception_case(client, exception)

      assert_equal false, result.success?
      assert_equal "connection_timeout", result.error_code
    end

    result = run_exception_case(client, Net::ReadTimeout.new)

    assert_equal false, result.success?
    assert_equal "read_timeout", result.error_code
  end

  test "post returns failure for connection errors" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)

    result = run_exception_case(client, Errno::ECONNREFUSED.new)
    assert_equal "connection_refused", result.error_code

    result = run_exception_case(client, Errno::ECONNRESET.new)
    assert_equal "connection_reset", result.error_code
  end

  test "post returns failure for dns errors" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)

    result = run_exception_case(client, SocketError.new("host not found"))

    assert_equal "dns_error", result.error_code
  end

  test "post returns failure for ssl errors" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)

    result = run_exception_case(client, OpenSSL::SSL::SSLError.new("bad cert"))

    assert_equal "ssl_error", result.error_code
  end

  test "post measures duration for exception cases" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    exception = Timeout::Error.new
    http = build_http_for_exception(exception)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)
    Process.stubs(:clock_gettime).returns(2.0, 2.5)

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal 500, result.duration_ms
  end

  test "post follows 301 redirects" do
    assert_follows_redirect("301")
  end

  test "post follows 302 redirects" do
    assert_follows_redirect("302")
  end

  test "post follows 303 redirects" do
    assert_follows_redirect("303")
  end

  test "post follows 307 redirects" do
    assert_follows_redirect("307")
  end

  test "post follows 308 redirects" do
    assert_follows_redirect("308")
  end

  test "post returns failure when too many redirects" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    redirect_urls = (1..6).map { |index| "https://example.test/redirect-#{index}" }
    responses = redirect_urls.map { |url| build_redirect_response("302", url) }
    http_mocks = responses.map { |response| build_http(response) }
    Net::HTTP.stubs(:new).returns(*http_mocks)

    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(build_request)
    redirect_urls.first(5).each do |url|
      Net::HTTP::Post.expects(:new).with(URI.parse(url).request_uri, @headers).returns(build_request)
    end

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal false, result.success?
    assert_equal "too_many_redirects", result.error_code
    assert_equal redirect_urls.last, result.final_url
  end

  test "post returns failure for insecure redirect" do
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    redirect_url = "http://example.test/insecure"
    response = build_redirect_response("302", redirect_url)
    http = build_http(response)
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(build_request)

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal false, result.success?
    assert_equal "insecure_redirect", result.error_code
    assert_equal redirect_url, result.final_url
  end

  private

  def build_request
    request = mock
    request.expects(:body=).with(@payload)
    request
  end

  def build_response(code, body)
    response = mock
    response.stubs(:code).returns(code)
    response.stubs(:body).returns(body)
    response
  end

  def build_redirect_response(code, location)
    response = build_response(code, "")
    response.stubs(:[]).with("location").returns(location)
    response
  end

  def run_exception_case(client, exception)
    http = build_http_for_exception(exception)
    request = build_request
    Net::HTTP.stubs(:new).returns(http)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(request)

    client.post(url: @url, payload: @payload, headers: @headers)
  end

  def build_http_for_exception(exception, use_ssl: true)
    http = mock
    http.stubs(:use_ssl=)
    http.stubs(:use_ssl?).returns(use_ssl)
    http.stubs(:verify_mode=)
    http.stubs(:open_timeout=)
    http.stubs(:read_timeout=)
    http.stubs(:start).raises(exception)
    http
  end

  def build_http(response, use_ssl: true)
    http = mock
    http.stubs(:use_ssl=)
    http.stubs(:use_ssl?).returns(use_ssl)
    http.stubs(:verify_mode=)
    http.stubs(:open_timeout=)
    http.stubs(:read_timeout=)
    http.stubs(:request).returns(response)
    http.stubs(:start).yields(http).returns(response)
    http
  end

  def assert_follows_redirect(code)
    client = RedmineWebhookPlugin::Webhook::HttpClient.new(timeout: 10, ssl_verify: true)
    redirect_url = "https://example.test/redirected"
    redirect_response = build_redirect_response(code, redirect_url)
    success_response = build_response("200", "ok")
    http_first = build_http(redirect_response)
    http_second = build_http(success_response)
    Net::HTTP.stubs(:new).returns(http_first, http_second)
    Net::HTTP::Post.expects(:new).with("/webhook", @headers).returns(build_request)
    Net::HTTP::Post.expects(:new).with("/redirected", @headers).returns(build_request)

    result = client.post(url: @url, payload: @payload, headers: @headers)

    assert_equal true, result.success?
    assert_equal 200, result.http_status
    assert_equal redirect_url, result.final_url
  end
end
