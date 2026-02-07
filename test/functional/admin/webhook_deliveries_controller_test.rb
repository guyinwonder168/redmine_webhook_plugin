require File.expand_path("../../test_helper", __dir__)

class Admin::WebhookDeliveriesControllerTest < Redmine::ControllerTest
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

  test "index renders deliveries table with correct headers" do
    @request.session[:user_id] = @admin.id
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    )

    get :index

    assert_response :success
    assert_select "table.webhook-deliveries" do
      assert_select "th", text: /ID/
      assert_select "th", text: /Endpoint/
      assert_select "th", text: /Event Type/
      assert_select "th", text: /Action/
      assert_select "th", text: /Status/
      assert_select "th", text: /HTTP Status/
      assert_select "th", text: /Created/
    end
  end

  test "index includes filter form" do
    @request.session[:user_id] = @admin.id

    get :index

    assert_response :success
    assert_select "form[action=?][method=get]", admin_webhook_deliveries_path do
      assert_select "select[name='endpoint_id']"
      assert_select "input[name='event_type']"
      assert_select "select[name='status']"
      assert_select "input[name='event_id']"
      assert_select "input[type=submit]"
    end
  end

  test "index filters deliveries by endpoint" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test Endpoint",
      url: "https://example.com/webhook"
    )
    d1 = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    )
    d2 = RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    )

    @request.session[:user_id] = @admin.id
    get :index, params: { endpoint_id: endpoint.id }

    assert_response :success
    assert_select "table.webhook-deliveries tbody tr", count: 1
    assert_select "td", text: d1.id.to_s
    refute_select "td", text: d2.id.to_s
  end

  test "show renders delivery details" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test Endpoint",
      url: "https://example.com/webhook"
    )
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-123",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      http_status: 200,
      attempt_count: 1,
      duration_ms: 245,
      response_body_excerpt: '{"status":"ok"}',
      error_code: nil,
      delivered_at: Time.current
    )

    @request.session[:user_id] = @admin.id
    get :show, params: { id: delivery.id }

    assert_response :success
    assert_select "h2", text: /Delivery #\d+/
    assert_select ".delivery-status", text: /success/i
    assert_select ".endpoint-info", text: /Test Endpoint/
    assert_select ".endpoint-url", text: /https:\/\/example.com\/webhook/
    assert_select ".event-info", text: /evt-123/
    assert_select ".http-status", text: /200/
    assert_select ".duration", text: /245/
    assert_select ".attempt-count", text: /1/
  end

  test "replay action resets delivery and enqueues job" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test Endpoint",
      url: "https://example.com/webhook"
    )
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-123",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      http_status: 500,
      attempt_count: 3,
      delivered_at: 1.hour.ago,
      response_body_excerpt: '{"error":"internal"}'
    )

    @request.session[:user_id] = @admin.id

    # Mock DeliveryJob enqueue to avoid actual job execution
    if defined?(ActiveJob)
      ActiveJob::Base.queue_adapter = :test
      RedmineWebhookPlugin::Webhook::DeliveryJob.expects(:perform_later).with(delivery.id).once
    end

    post :replay, params: { id: delivery.id }

    # Verify delivery was reset
    delivery.reload
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery.status
    assert_nil delivery.http_status
    assert_equal 0, delivery.attempt_count
    assert_nil delivery.delivered_at
    assert_nil delivery.response_body_excerpt
    assert_nil delivery.error_code

    # Verify redirect and flash
    assert_redirected_to admin_webhook_delivery_path(delivery)
    assert_not_nil flash[:notice]
    assert_match(/queued for replay/i, flash[:notice])
  end

  test "bulk_replay action resets multiple deliveries and enqueues jobs" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test Endpoint",
      url: "https://example.com/webhook"
    )
    delivery1 = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-001",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      http_status: 500,
      attempt_count: 2,
      delivered_at: 1.hour.ago
    )
    delivery2 = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-002",
      event_type: "issue",
      action: "updated",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED,
      http_status: 502,
      attempt_count: 1,
      delivered_at: 30.minutes.ago
    )
    delivery3 = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-003",
      event_type: "time_entry",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      http_status: 200,
      attempt_count: 1,
      delivered_at: 2.hours.ago
    )

    @request.session[:user_id] = @admin.id

    # Mock DeliveryJob enqueue to avoid actual job execution
    if defined?(ActiveJob)
      ActiveJob::Base.queue_adapter = :test
      RedmineWebhookPlugin::Webhook::DeliveryJob.expects(:perform_later).with(delivery1.id).once
      RedmineWebhookPlugin::Webhook::DeliveryJob.expects(:perform_later).with(delivery2.id).once
    end

    # Bulk replay only the first two deliveries
    post :bulk_replay, params: { ids: [delivery1.id, delivery2.id] }

    # Verify delivery1 was reset
    delivery1.reload
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery1.status
    assert_nil delivery1.http_status
    assert_equal 0, delivery1.attempt_count
    assert_nil delivery1.delivered_at

    # Verify delivery2 was reset
    delivery2.reload
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery2.status
    assert_nil delivery2.http_status
    assert_equal 0, delivery2.attempt_count
    assert_nil delivery2.delivered_at

    # Verify delivery3 was NOT modified (not in the ids array)
    delivery3.reload
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::SUCCESS, delivery3.status
    assert_equal 200, delivery3.http_status
    assert_equal 1, delivery3.attempt_count
    assert_not_nil delivery3.delivered_at

    # Verify redirect and flash
    assert_redirected_to admin_webhook_deliveries_path
    assert_not_nil flash[:notice]
    assert_match(/2 deliveries queued for replay/i, flash[:notice])
  end

  test "bulk_replay with no ids shows flash warning" do
    @request.session[:user_id] = @admin.id

    post :bulk_replay, params: { ids: [] }

    assert_redirected_to admin_webhook_deliveries_path
    assert_not_nil flash[:warning]
    assert_match(/no deliveries selected/i, flash[:warning])
  end

  test "index uses pagination and assigns delivery pages" do
    # Create 55 deliveries to test pagination (50 per page)
    55.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        event_id: SecureRandom.uuid,
        event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
      )
    end

    @request.session[:user_id] = @admin.id
    get :index

    assert_response :success

    # Verify pagination links are shown
    assert_select "span.pagination"
    assert_select "span.pagination a", count: 2  # Prev/Next links
  end

  test "index respects per_page limit of 50" do
    60.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        event_id: SecureRandom.uuid,
        event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
      )
    end

    @request.session[:user_id] = @admin.id
    get :index

    assert_response :success
    # Check that table has 50 rows (deliveries)
    assert_select "table.webhook-deliveries tbody tr", count: 50
  end

  test "index supports page parameter" do
    # Create 55 deliveries
    deliveries = []
    55.times do |i|
      deliveries << RedmineWebhookPlugin::Webhook::Delivery.create!(
        event_id: SecureRandom.uuid,
        event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
      )
    end

    @request.session[:user_id] = @admin.id
    get :index, params: { page: 2 }

    assert_response :success
    # Page 2 should have 5 items (55 total - 50 on page 1)
    assert_select "table.webhook-deliveries tbody tr", count: 5
  end

  test "index pagination preserves filters" do
    endpoint1 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint 1",
      url: "https://example.com/1"
    )

    # Create 60 deliveries for endpoint1 (enough for 2 pages with 50 per page)
    60.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        endpoint_id: endpoint1.id,
        event_id: SecureRandom.uuid,
        event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
      )
    end

    @request.session[:user_id] = @admin.id
    # Request page 1 with filter for endpoint1
    get :index, params: { endpoint_id: endpoint1.id, page: 1 }

    assert_response :success
    # Verify filter is preserved in pagination links
    assert_select "span.pagination a[href*=?]", "endpoint_id=#{endpoint1.id}"
  end

  test "export returns CSV with correct headers" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test Endpoint",
      url: "https://example.com/webhook"
    )
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-123",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      http_status: 200
    )

    @request.session[:user_id] = @admin.id
    get :index, format: :csv

    assert_response :success
    assert_equal "text/csv; header=present", response.media_type

    csv_lines = response.body.split("\n")
    headers = csv_lines.first.split(",").map(&:strip)
    assert_equal "ID", headers[0]
    assert_equal "Endpoint", headers[1]
    assert_equal "Event Type", headers[2]
    assert_equal "Action", headers[3]
    assert_equal "Status", headers[4]
    assert_equal "HTTP Status", headers[5]
    assert_equal "Created At", headers[6]
  end

  test "export includes delivery data in CSV" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test Endpoint",
      url: "https://example.com/webhook"
    )
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: "evt-123",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS,
      http_status: 200
    )

    @request.session[:user_id] = @admin.id
    get :index, format: :csv

    assert_response :success
    csv_lines = response.body.split("\n")

    # Verify data row (skip header)
    data_row = csv_lines[1]
    assert_match(/#{delivery.id}/, data_row)
    assert_match(/Test Endpoint/, data_row)
    assert_match(/issue/, data_row)
    assert_match(/created/, data_row)
    assert_match(/success/, data_row)
    assert_match(/200/, data_row)
  end

  test "export limits to 1000 most recent records" do
    # Create 1005 deliveries
    1005.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        event_id: "evt-#{i}",
        event_type: "issue",
        action: "created",
        status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
      )
    end

    @request.session[:user_id] = @admin.id
    get :index, format: :csv

    assert_response :success
    csv_lines = response.body.split("\n")

    # 1 header + 1000 data rows
    assert_equal 1001, csv_lines.length
  end

  test "export respects filters" do
    endpoint1 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint 1",
      url: "https://example.com/1"
    )
    endpoint2 = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Endpoint 2",
      url: "https://example.com/2"
    )

    # Create deliveries for both endpoints
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint1.id,
      event_id: "evt-1",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    )
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint2.id,
      event_id: "evt-2",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED
    )

    @request.session[:user_id] = @admin.id
    # Export with endpoint filter
    get :index, params: { endpoint_id: endpoint1.id }, format: :csv

    assert_response :success
    csv_lines = response.body.split("\n")

    # Should have 2 lines (header + 1 delivery)
    assert_equal 2, csv_lines.length
    assert_match(/Endpoint 1/, csv_lines[1])
    refute_match(/Endpoint 2/, csv_lines[1])
  end

  test "export sets correct filename" do
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      event_id: "evt-123",
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS
    )

    @request.session[:user_id] = @admin.id
    get :index, format: :csv

    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/webhook_deliveries\.csv/, response.headers["Content-Disposition"])
  end

  test "export handles empty deliveries list" do
    @request.session[:user_id] = @admin.id
    get :index, format: :csv

    assert_response :success
    csv_lines = response.body.split("\n")

    # Should only have header, no data rows
    assert_equal 1, csv_lines.length
    assert_equal "ID,Endpoint,Event Type,Action,Status,HTTP Status,Created At", csv_lines[0].strip
  end
end
