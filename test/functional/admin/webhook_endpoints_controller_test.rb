require File.expand_path("../../test_helper", __dir__)

class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    @routes = RedmineApp::Application.routes
    @admin = User.find(1)
    @non_admin = User.find(2)
    RedmineWebhookPlugin::Webhook::Delivery.delete_all
    RedmineWebhookPlugin::Webhook::Endpoint.delete_all
  end

  test "admin can access index" do
    @request.session[:user_id] = @admin.id
    get :index

    assert_response :success
  end

  test "index renders table and actions" do
    @request.session[:user_id] = @admin.id
    RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")

    get :index

    assert_select "table.webhook-endpoints" do
      assert_select "th", text: /Name/
      assert_select "th", text: /URL/
      assert_select "th", text: /Enabled/
      assert_select "th", text: /Actions|Action/
    end
    assert_select "a", text: /New Endpoint/
  end

  test "non-admin cannot access index" do
    @request.session[:user_id] = @non_admin.id
    get :index

    assert_response 403
  end

  test "new renders form with base fields" do
    @request.session[:user_id] = @admin.id

    get :new

    assert_response :success
    assert_select "form"
  end

  test "form includes webhook user and project selectors" do
    @request.session[:user_id] = @admin.id

    get :new

    assert_select "select[name='webhook_endpoint[webhook_user_id]']"
    assert_select "select[name='webhook_endpoint[project_ids][]']"
    assert_select "em", text: "Empty = all projects"
  end

  test "form includes issue and time entry event checkboxes" do
    @request.session[:user_id] = @admin.id

    get :new

    assert_select "input[type=checkbox][name='events[issue][created]']"
    assert_select "input[type=checkbox][name='events[issue][updated]']"
    assert_select "input[type=checkbox][name='events[issue][deleted]']"
    assert_select "input[type=checkbox][name='events[time_entry][created]']"
    assert_select "input[type=checkbox][name='events[time_entry][updated]']"
    assert_select "input[type=checkbox][name='events[time_entry][deleted]']"
  end

  test "create stores events_config from params" do
    @request.session[:user_id] = @admin.id

    post :create, params: {
      webhook_endpoint: {
        name: "Event Config",
        url: "https://example.com"
      },
      events: {
        issue: { created: "1", updated: "0", deleted: "1" },
        time_entry: { created: "1", updated: "1", deleted: "0" }
      }
    }

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.last
    assert_equal true, endpoint.events_config.dig("issue", "created")
    assert_equal false, endpoint.events_config.dig("issue", "updated")
    assert_equal true, endpoint.events_config.dig("issue", "deleted")
    assert_equal true, endpoint.events_config.dig("time_entry", "created")
  end

  test "form includes retry and request options" do
    @request.session[:user_id] = @admin.id

    get :new

    assert_select "input[name='retry[max_attempts]']"
    assert_select "input[name='retry[base_delay]']"
    assert_select "input[name='retry[max_delay]']"
    assert_select "input[name='webhook_endpoint[timeout]']"
    assert_select "input[name='webhook_endpoint[ssl_verify]']"
  end

  test "create stores retry_config" do
    @request.session[:user_id] = @admin.id

    post :create, params: {
      webhook_endpoint: { name: "Retry", url: "https://example.com" },
      retry: { max_attempts: "3", base_delay: "30", max_delay: "600" }
    }

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.last
    assert_equal 3, endpoint.retry_config["max_attempts"]
    assert_equal 30, endpoint.retry_config["base_delay"]
    assert_equal 600, endpoint.retry_config["max_delay"]
  end

  test "edit renders form" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Edit", url: "https://example.com")

    get :edit, params: { id: endpoint.id }

    assert_response :success
    assert_select "form"
  end

  test "update persists changes" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Old", url: "https://example.com")

    patch :update, params: { id: endpoint.id, webhook_endpoint: { name: "New" } }

    assert_redirected_to admin_webhook_endpoints_path
    assert_equal "New", endpoint.reload.name
  end

  test "destroy deletes endpoint and marks deliveries" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Delete", url: "https://example.com")

    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )

    assert_difference "RedmineWebhookPlugin::Webhook::Endpoint.count", -1 do
      delete :destroy, params: { id: endpoint.id }
    end

    assert_redirected_to admin_webhook_endpoints_path
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::ENDPOINT_DELETED, RedmineWebhookPlugin::Webhook::Delivery.last.status
  end

  test "toggle flips enabled flag" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Toggle", url: "https://example.com", enabled: true)

    patch :toggle, params: { id: endpoint.id }

    assert_redirected_to admin_webhook_endpoints_path
    assert_equal false, endpoint.reload.enabled
    assert_match /toggled/i, flash[:notice]
  end

  test "toggle can enable disabled endpoint" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Toggle", url: "https://example.com", enabled: false)

    patch :toggle, params: { id: endpoint.id }

    assert_redirected_to admin_webhook_endpoints_path
    assert_equal true, endpoint.reload.enabled
    assert_match /toggled/i, flash[:notice]
  end

  test "test action creates a test delivery" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")

    assert_difference "RedmineWebhookPlugin::Webhook::Delivery.count", 1 do
      post :test, params: { id: endpoint.id }
    end

    delivery = RedmineWebhookPlugin::Webhook::Delivery.last
    assert_equal true, delivery.is_test
    assert_equal "test", delivery.event_type
    assert_equal "test", delivery.action
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery.status
    assert_equal endpoint.id, delivery.endpoint_id
    assert_redirected_to admin_webhook_endpoints_path
    assert_match /test.*queued/i, flash[:notice]
  end

  test "test action requires admin" do
    @request.session[:user_id] = @non_admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")

    post :test, params: { id: endpoint.id }

    assert_response 403
    assert_equal 0, RedmineWebhookPlugin::Webhook::Delivery.count
  end

  test "test action uses synthetic payload" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")

    post :test, params: { id: endpoint.id }

    delivery = RedmineWebhookPlugin::Webhook::Delivery.last
    assert_equal "test", delivery.event_type
    assert_equal "test", delivery.action
    assert_equal true, delivery.is_test
  end

  test "create warns if webhook user has no API key" do
    @request.session[:user_id] = @admin.id
    user = User.find(2)

    Token.where(user_id: user.id, action: "api").delete_all

    post :create, params: {
      webhook_endpoint: {
        name: "Warn",
        url: "https://example.com",
        webhook_user_id: user.id
      }
    }

    assert_equal "Webhook user has no API key", flash[:warning]
  end
end
