# Last Gap Implementation Plan: Redmine Webhook Plugin v1.0.0 (TDD)

**Goal:** Address final functional gaps, PRD alignment, and UI/UX polish using Test-Driven Development.

---

## Task 1: Admin Accessibility & Navigation

### Step 1: Write the failing tests
**Files:**
- `test/functional/admin/webhook_navigation_test.rb`

```ruby
require File.expand_path("../../../test_helper", __dir__)

class Admin::WebhookNavigationTest < ActionController::TestCase
  tests Admin::WebhookEndpointsController

  def setup
    @request.session[:user_id] = 1 # admin
  end

  test "admin menu includes Deliveries link" do
    get :index
    assert_select "a.icon-webhook", text: /Deliveries/
  end

  test "endpoints index includes link to filtered deliveries" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Test", url: "http://x.y", webhook_user_id: 1
    )
    get :index
    assert_select "a[href=?]", admin_webhook_deliveries_path(endpoint_id: endpoint.id)
  end
end
```

### Step 2: Run tests to verify failure
Expected: FAIL - Menu link not defined; Cross-link not in view.

### Step 3: Implement
- Modify `init.rb`: Add `menu :admin_menu, :webhook_deliveries, ...`
- Modify `app/views/admin/webhook_endpoints/index.html.erb`: Add the link.

### Step 4: Run tests to verify success

---

## Task 2: Global Delivery Pause

### Step 1: Write the failing tests
**Files:**
- `test/unit/webhook/global_pause_test.rb`

```ruby
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::GlobalPauseTest < ActiveSupport::TestCase
  def setup
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Pause Test", url: "http://x.y", webhook_user_id: 1, enabled: true
    )
    # Enable events for issue created
    @endpoint.events_config = { "issue" => { "created" => true } }
    @endpoint.save!
  end

  test "Dispatcher does not create deliveries when paused" do
    Setting.plugin_redmine_webhook_plugin = { "deliveries_paused" => "1" }
    
    event_data = { event_id: "1", event_type: "issue", action: "created", project_id: 1 }
    deliveries = RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_data)
    
    assert_empty deliveries, "Should not create deliveries when paused"
  end

  test "Sender does not send when paused" do
    Setting.plugin_redmine_webhook_plugin = { "deliveries_paused" => "1" }
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: @endpoint.id, event_id: "2", event_type: "test", action: "test",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
    )
    
    RedmineWebhookPlugin::Webhook::Sender.send(delivery)
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery.reload.status
  end
end
```

### Step 2: Run tests to verify failure
Expected: FAIL - Deliveries still created and sent.

### Step 3: Implement
- Update `app/services/webhook/dispatcher.rb` to check setting.
- Update `app/services/webhook/sender.rb` to check setting.

### Step 4: Run tests to verify success

---

## Task 3: DB Runner Batch Limits

### Step 1: Write the failing test
**Files:**
- `test/unit/webhook/rake_batch_test.rb`

```ruby
require File.expand_path("../../test_helper", __dir__)
require "rake"

class RedmineWebhookPlugin::Webhook::RakeBatchTest < ActiveSupport::TestCase
  def setup
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(
      name: "Batch", url: "http://x.y", webhook_user_id: 1
    )
    60.times do |i|
      RedmineWebhookPlugin::Webhook::Delivery.create!(
        endpoint_id: @endpoint.id, event_id: "e-#{i}", event_type: "test", action: "test",
        status: RedmineWebhookPlugin::Webhook::Delivery::PENDING
      )
    end
    RedmineApp::Application.load_tasks if Rake::Task.tasks.empty?
  end

  test "process task respects BATCH_SIZE limit" do
    ENV['BATCH_SIZE'] = '10'
    # Mock Sender to avoid actual HTTP calls and just mark success
    RedmineWebhookPlugin::Webhook::Sender.stub :send, ->(d) { d.update!(status: 'success') } do
      Rake::Task["redmine:webhooks:process"].execute
    end
    
    success_count = RedmineWebhookPlugin::Webhook::Delivery.where(status: 'success').count
    assert_equal 10, success_count
  end
end
```

### Step 2: Run test to verify failure
Expected: FAIL - Processes all 60.

### Step 3: Implement
- Modify `lib/tasks/webhook.rake`: Add `.limit(ENV['BATCH_SIZE'] || 50)`.

### Step 4: Run test to verify success

---

## Task 4: Soft FIFO Stagger

### Step 1: Write the failing test
**Files:**
- `test/unit/webhook/dispatcher_stagger_test.rb`

```ruby
require File.expand_path("../../test_helper", __dir__)

class RedmineWebhookPlugin::Webhook::DispatcherStaggerTest < ActiveSupport::TestCase
  test "dispatch enqueues jobs with stagger delay" do
    # Create 3 endpoints
    3.times { |i| RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "E#{i}", url: "http://x.y", enabled: true, events_config: {"issue"=>{"created"=>true}}) }
    
    # Mock DeliveryJob.perform_later to track arguments
    mock_job = MiniTest::Mock.new
    # Expect 3 calls with increasing wait
    mock_job.expect(:perform_later, nil, [Integer, {wait: 0.0.seconds}])
    mock_job.expect(:perform_later, nil, [Integer, {wait: 0.5.seconds}])
    mock_job.expect(:perform_later, nil, [Integer, {wait: 1.0.seconds}])

    RedmineWebhookPlugin::Webhook::ExecutionMode.stub :detect, :activejob do
      RedmineWebhookPlugin::Webhook::DeliveryJob.stub :perform_later, ->(id, opts={}) { mock_job.perform_later(id, opts) } do
        RedmineWebhookPlugin::Webhook::Dispatcher.dispatch(event_type: "issue", action: "created")
      end
    end
    mock_job.verify
  end
end
```

### Step 2: Run test to verify failure
Expected: FAIL - No `wait` option passed.

### Step 3: Implement
- Modify `app/services/webhook/dispatcher.rb`.

### Step 4: Run test to verify success

---

## Task 5: Payload Builder Alignment (last_note)

### Step 1: Update existing test
- Modify `test/unit/webhook/payload_builder_test.rb`.
- Change `assert result.key?(:journal)` to `assert result.key?(:last_note)`.

### Step 2: Run test to verify failure

### Step 3: Implement
- Modify `app/services/webhook/payload_builder.rb`.
- Rename `:journal` key to `:last_note`.

### Step 4: Run test to verify success

---

## Task 6: Cross-version verification (Final)

1. Run full suite on all versions:
```bash
VERSION=all tools/test/run-test.sh
```

2. Verify README and CHANGELOG updates.
3. Commit with "v1.0.0 Release Candidate" summary.
