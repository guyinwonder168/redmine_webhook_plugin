# Final Phase Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provide delivery logs UI, replay capabilities, CSV export, retention purge, and settings for webhook operations.

**Architecture:** Admin UI controllers for deliveries with index/show actions, filter helpers, and replay endpoints. A CSV exporter streams filtered data. Rake task handles retention purge. Settings are added in plugin settings to control execution and retention.

**Tech Stack:** Ruby/Rails, Redmine plugin API, ActiveRecord, Minitest

**Depends on:** Integration phase complete

## Redmine 7.0+ Compatibility

- Detect native webhooks via `defined?(::Webhook) && ::Webhook < ApplicationRecord`.
- When native exists, disable or bypass native delivery; the plugin remains authoritative.
- Use `RedmineWebhookPlugin::` for plugin service namespaces to avoid conflicts with native `Webhook`.

---

## Testing Environment (Podman)

All tests run inside Podman containers to ensure consistent Ruby/Rails versions. The workspace has three Redmine versions available:

| Version | Directory | Image | Ruby |
|---------|-----------|-------|------|
| 5.1.0 | `.redmine-test/redmine-5.1.0/` | `redmine-dev:5.1.0` | 3.2.2 |
| 5.1.10 | `.redmine-test/redmine-5.1.10/` | `redmine-dev:5.1.10` | 3.2.2 |
| 6.1.0 | `.redmine-test/redmine-6.1.0/` | `redmine-dev:6.1.0` | 3.3.4 |
| 7.0.0-dev | `.redmine-test/redmine-7.0.0-dev/` | `redmine-dev:7.0.0-dev` | 3.3.4 |

> **IMPORTANT:** Every task MUST be verified on ALL FOUR Redmine versions before marking complete.

### Cross-Version Test Pattern

After implementing each task, run the test on all three versions:

```bash
# From /media/eddy/hdd/Project/redmine_webhook_plugin

# 5.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'

# 7.0.0-dev
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-7.0.0-dev:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/7.0.0-dev:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:7.0.0-dev \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/TESTFILE.rb -v'
```

---

## Task 1: Deliveries Controller Skeleton

**Files:**
- Create: `app/controllers/admin/webhook_deliveries_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb
require File.expand_path("../../test_helper", __dir__)

class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  fixtures :users

  def setup
    @admin = User.find(1)
  end

  test "admin can access deliveries index" do
    @request.session[:user_id] = @admin.id
    get :index

    assert_response :success
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL with uninitialized constant Admin::WebhookDeliveriesController

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_deliveries, only: [:index, :show]
  end
end
```

```ruby
# app/controllers/admin/webhook_deliveries_controller.rb
class Admin::WebhookDeliveriesController < AdminController
  layout "admin"

  def index
    @deliveries = RedmineWebhookPlugin::Webhook::Delivery.order(created_at: :desc).limit(50)
  end

  def show
    @delivery = RedmineWebhookPlugin::Webhook::Delivery.find(params[:id])
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_deliveries_controller.rb config/routes.rb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add webhook deliveries controller skeleton"
```

---

## Task 2: Deliveries Index View

**Files:**
- Create: `app/views/admin/webhook_deliveries/index.html.erb`
- Modify: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb - add to existing file
class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  test "index renders deliveries table" do
    @request.session[:user_id] = @admin.id
    get :index

    assert_select "table.webhook-deliveries"
    assert_select "th", text: "ID"
    assert_select "th", text: "Endpoint"
    assert_select "th", text: "Event Type"
    assert_select "th", text: "Action"
    assert_select "th", text: "Status"
    assert_select "th", text: "HTTP"
    assert_select "th", text: "Created"
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL with missing template or selectors

**Step 3: Write minimal implementation**

```erb
<!-- app/views/admin/webhook_deliveries/index.html.erb -->
<h2><%= l(:label_webhook_deliveries) %></h2>

<table class="list webhook-deliveries">
  <thead>
    <tr>
      <th>ID</th>
      <th><%= l(:label_webhook_endpoint) %></th>
      <th><%= l(:label_event_type) %></th>
      <th><%= l(:label_action) %></th>
      <th><%= l(:label_status) %></th>
      <th><%= l(:label_http_status) %></th>
      <th><%= l(:label_created_on) %></th>
    </tr>
  </thead>
  <tbody>
    <% @deliveries.each do |delivery| %>
      <tr>
        <td><%= link_to delivery.id, admin_webhook_delivery_path(delivery) %></td>
        <td><%= delivery.endpoint_id %></td>
        <td><%= delivery.event_type %></td>
        <td><%= delivery.action %></td>
        <td><%= delivery.status %></td>
        <td><%= delivery.http_status %></td>
        <td><%= format_time(delivery.created_at) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 2 tests, 0 failures

**Step 6: Commit**

```bash
git add app/views/admin/webhook_deliveries/index.html.erb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add deliveries index view"
```

---

## Task 3: Filters and Search Form

**Files:**
- Modify: `app/controllers/admin/webhook_deliveries_controller.rb`
- Modify: `app/views/admin/webhook_deliveries/index.html.erb`
- Modify: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb - add to existing file
class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  test "index includes filter form" do
    @request.session[:user_id] = @admin.id
    get :index

    assert_select "form#delivery-filters"
    assert_select "select[name='endpoint_id']"
    assert_select "select[name='event_type']"
    assert_select "select[name='status']"
    assert_select "input[name='event_id']"
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL - filter form missing

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_deliveries_controller.rb
class Admin::WebhookDeliveriesController < AdminController
  layout "admin"

  def index
    @endpoints = RedmineWebhookPlugin::Webhook::Endpoint.order(:name)
    scope = RedmineWebhookPlugin::Webhook::Delivery.order(created_at: :desc)

    scope = scope.where(endpoint_id: params[:endpoint_id]) if params[:endpoint_id].present?
    scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(event_id: params[:event_id]) if params[:event_id].present?

    @deliveries = scope.limit(50)
  end
end
```

```erb
<!-- app/views/admin/webhook_deliveries/index.html.erb - add filter form -->
<%= form_with url: admin_webhook_deliveries_path, method: :get, id: "delivery-filters", local: true do %>
  <fieldset class="box">
    <legend><%= l(:label_filter_plural) %></legend>
    <label><%= l(:label_webhook_endpoint) %>
      <%= select_tag :endpoint_id, options_from_collection_for_select(@endpoints, :id, :name, params[:endpoint_id]), include_blank: true %>
    </label>
    <label><%= l(:label_event_type) %>
      <%= select_tag :event_type, options_for_select(["issue", "time_entry"], params[:event_type]), include_blank: true %>
    </label>
    <label><%= l(:label_status) %>
      <%= select_tag :status, options_for_select(RedmineWebhookPlugin::Webhook::Delivery::STATUSES, params[:status]), include_blank: true %>
    </label>
    <label><%= l(:label_event_id) %>
      <%= text_field_tag :event_id, params[:event_id] %>
    </label>
    <%= submit_tag l(:button_apply), class: "button" %>
    <%= link_to l(:button_clear), admin_webhook_deliveries_path, class: "button" %>
  </fieldset>
<% end %>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_deliveries_controller.rb app/views/admin/webhook_deliveries/index.html.erb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add delivery filters and search"
```

---

## Task 4: Delivery Detail View

**Files:**
- Create: `app/views/admin/webhook_deliveries/show.html.erb`
- Modify: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb - add to existing file
class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  test "show renders delivery details" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Show", url: "https://example.com")
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: { test: true }.to_json
    )

    get :show, params: { id: delivery.id }

    assert_select "h2", text: /Delivery/ 
    assert_select "pre.payload"
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL with missing template

**Step 3: Write minimal implementation**

```erb
<!-- app/views/admin/webhook_deliveries/show.html.erb -->
<h2><%= l(:label_webhook_delivery) %> #<%= @delivery.id %></h2>

<table class="attributes">
  <tr><th><%= l(:label_event_id) %></th><td><%= @delivery.event_id %></td></tr>
  <tr><th><%= l(:label_event_type) %></th><td><%= @delivery.event_type %></td></tr>
  <tr><th><%= l(:label_action) %></th><td><%= @delivery.action %></td></tr>
  <tr><th><%= l(:label_status) %></th><td><%= @delivery.status %></td></tr>
  <tr><th><%= l(:label_http_status) %></th><td><%= @delivery.http_status %></td></tr>
  <tr><th><%= l(:label_api_key_fingerprint) %></th><td><%= @delivery.api_key_fingerprint %></td></tr>
  <tr><th><%= l(:label_response_excerpt) %></th><td><%= @delivery.response_body_excerpt %></td></tr>
</table>

<h3><%= l(:label_payload) %></h3>
<pre class="payload"><%= @delivery.payload %></pre>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add app/views/admin/webhook_deliveries/show.html.erb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add delivery show view"
```

---

## Task 5: Replay Action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/webhook_deliveries_controller.rb`
- Modify: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb - add to existing file
class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  test "replay resets delivery and enqueues" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Replay", url: "https://example.com")
    delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "issue",
      action: "created",
      status: RedmineWebhookPlugin::Webhook::Delivery::FAILED
    )

    post :replay, params: { id: delivery.id }

    assert_redirected_to admin_webhook_delivery_path(delivery)
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery.reload.status
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL with missing route/action

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_deliveries, only: [:index, :show] do
      post :replay, on: :member
    end
  end
end
```

```ruby
# app/controllers/admin/webhook_deliveries_controller.rb
class Admin::WebhookDeliveriesController < AdminController
  layout "admin"

  def index
    # ... existing index logic ...
  end

  def show
    @delivery = RedmineWebhookPlugin::Webhook::Delivery.find(params[:id])
  end

  def replay
    delivery = RedmineWebhookPlugin::Webhook::Delivery.find(params[:id])
    delivery.reset_for_replay!

    RedmineWebhookPlugin::Webhook::DeliveryJob.perform_later(delivery.id) if RedmineWebhookPlugin::Webhook::ExecutionMode.detect == :activejob

    flash[:notice] = l(:notice_webhook_delivery_replayed)
    redirect_to admin_webhook_delivery_path(delivery)
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 5 tests, 0 failures

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/webhook_deliveries_controller.rb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add replay action for deliveries"
```

---

## Task 6: Bulk Replay Action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/webhook_deliveries_controller.rb`
- Modify: `app/views/admin/webhook_deliveries/index.html.erb`
- Modify: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb - add to existing file
class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  test "bulk replay resets selected deliveries" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Bulk", url: "https://example.com")
    delivery1 = RedmineWebhookPlugin::Webhook::Delivery.create!(endpoint_id: endpoint.id, event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: RedmineWebhookPlugin::Webhook::Delivery::FAILED)
    delivery2 = RedmineWebhookPlugin::Webhook::Delivery.create!(endpoint_id: endpoint.id, event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: RedmineWebhookPlugin::Webhook::Delivery::FAILED)

    post :bulk_replay, params: { delivery_ids: [delivery1.id, delivery2.id] }

    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery1.reload.status
    assert_equal RedmineWebhookPlugin::Webhook::Delivery::PENDING, delivery2.reload.status
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL with missing action/route

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_deliveries, only: [:index, :show] do
      post :replay, on: :member
      post :bulk_replay, on: :collection
    end
  end
end
```

```ruby
# app/controllers/admin/webhook_deliveries_controller.rb
class Admin::WebhookDeliveriesController < AdminController
  layout "admin"

  # ... index/show/replay ...

  def bulk_replay
    ids = Array(params[:delivery_ids]).map(&:to_i)
    deliveries = RedmineWebhookPlugin::Webhook::Delivery.where(id: ids)
    deliveries.each(&:reset_for_replay!)

    flash[:notice] = l(:notice_webhook_bulk_replay, count: deliveries.count)
    redirect_to admin_webhook_deliveries_path
  end
end
```

```erb
<!-- app/views/admin/webhook_deliveries/index.html.erb - add bulk replay controls -->
<%= form_with url: bulk_replay_admin_webhook_deliveries_path, method: :post, local: true do %>
  <table class="list webhook-deliveries">
    <thead>
      <tr>
        <th></th>
        <!-- existing headers -->
      </tr>
    </thead>
    <tbody>
      <% @deliveries.each do |delivery| %>
        <tr>
          <td><%= check_box_tag "delivery_ids[]", delivery.id %></td>
          <!-- existing columns -->
        </tr>
      <% end %>
    </tbody>
  </table>
  <%= submit_tag l(:label_replay_selected), class: "button" %>
<% end %>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 6 tests, 0 failures

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/webhook_deliveries_controller.rb app/views/admin/webhook_deliveries/index.html.erb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add bulk replay"
```

---

## Task 7: CSV Export

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/webhook_deliveries_controller.rb`
- Test: `test/functional/admin/webhook_deliveries_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_deliveries_controller_test.rb - add to existing file
class Admin::WebhookDeliveriesControllerTest < ActionController::TestCase
  test "export returns csv" do
    @request.session[:user_id] = @admin.id
    get :export

    assert_response :success
    assert_equal "text/csv", @response.media_type
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```


Expected: FAIL with missing route/action

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_deliveries, only: [:index, :show] do
      post :replay, on: :member
      post :bulk_replay, on: :collection
      get :export, on: :collection
    end
  end
end
```

```ruby
# app/controllers/admin/webhook_deliveries_controller.rb
require "csv"

class Admin::WebhookDeliveriesController < AdminController
  layout "admin"

  # ... index/show/replay/bulk_replay ...

  def export
    csv = CSV.generate do |rows|
      rows << %w[delivery_id event_id endpoint_id event_type action resource_id status attempt_count http_status error_code created_at delivered_at]
      RedmineWebhookPlugin::Webhook::Delivery.order(created_at: :desc).limit(1000).find_each do |delivery|
        rows << [
          delivery.id,
          delivery.event_id,
          delivery.endpoint_id,
          delivery.event_type,
          delivery.action,
          delivery.resource_id,
          delivery.status,
          delivery.attempt_count,
          delivery.http_status,
          delivery.error_code,
          delivery.created_at,
          delivery.delivered_at
        ]
      end
    end

    send_data csv, filename: "webhook-deliveries.csv", type: "text/csv"
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_deliveries_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 7 tests, 0 failures

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/webhook_deliveries_controller.rb test/functional/admin/webhook_deliveries_controller_test.rb
git commit -m "feat(final): add deliveries CSV export"
```

---

## Task 8: Retention Purge Task

**Files:**
- Modify: `lib/tasks/webhook.rake`
- Test: `test/unit/webhook_rake_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/webhook_rake_test.rb - add to existing file
class WebhookRakeTest < ActiveSupport::TestCase
  test "purge task is defined" do
    Rake.application.rake_require "tasks/webhook"
    assert Rake::Task.task_defined?("redmine:webhooks:purge")
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```


Expected: FAIL - task not defined

**Step 3: Write minimal implementation**

```ruby
# lib/tasks/webhook.rake
namespace :redmine do
  namespace :webhooks do
    desc "Purge old webhook deliveries"
    task :purge => :environment do
      # Implementation added in next task
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/tasks/webhook.rake test/unit/webhook_rake_test.rb
git commit -m "feat(final): add webhook purge rake task skeleton"
```

---

## Task 9: Retention Purge Logic

**Files:**
- Modify: `lib/tasks/webhook.rake`
- Modify: `test/unit/webhook_rake_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook_rake_test.rb - add to existing file
class WebhookRakeTest < ActiveSupport::TestCase
  test "purge removes old deliveries" do
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Purge", url: "https://example.com")
    old_delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(endpoint_id: endpoint.id, event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS, delivered_at: 10.days.ago)
    fresh_delivery = RedmineWebhookPlugin::Webhook::Delivery.create!(endpoint_id: endpoint.id, event_id: SecureRandom.uuid, event_type: "issue", action: "created", status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS, delivered_at: 1.day.ago)

    ENV["RETENTION_DAYS_SUCCESS"] = "7"
    Rake::Task["redmine:webhooks:purge"].reenable
    Rake::Task["redmine:webhooks:purge"].invoke

    assert_not RedmineWebhookPlugin::Webhook::Delivery.exists?(old_delivery.id)
    assert RedmineWebhookPlugin::Webhook::Delivery.exists?(fresh_delivery.id)
  ensure
    ENV.delete("RETENTION_DAYS_SUCCESS")
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```


Expected: FAIL - purge does nothing

**Step 3: Write minimal implementation**

```ruby
# lib/tasks/webhook.rake
namespace :redmine do
  namespace :webhooks do
    desc "Purge old webhook deliveries"
    task :purge => :environment do
      success_days = (ENV["RETENTION_DAYS_SUCCESS"] || 7).to_i
      failed_days = (ENV["RETENTION_DAYS_FAILED"] || 7).to_i

      success_cutoff = success_days.days.ago
      failed_cutoff = failed_days.days.ago

      success_count = RedmineWebhookPlugin::Webhook::Delivery.where(status: RedmineWebhookPlugin::Webhook::Delivery::SUCCESS).where("delivered_at < ?", success_cutoff).delete_all
      failed_count = RedmineWebhookPlugin::Webhook::Delivery.where(status: [RedmineWebhookPlugin::Webhook::Delivery::FAILED, RedmineWebhookPlugin::Webhook::Delivery::DEAD]).where("delivered_at < ?", failed_cutoff).delete_all

      puts "Purged #{success_count} success deliveries and #{failed_count} failed deliveries"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_rake_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/tasks/webhook.rake test/unit/webhook_rake_test.rb
git commit -m "feat(final): add retention purge logic"
```

---

## Task 10: Plugin Settings

**Files:**
- Modify: `init.rb`
- Create: `app/views/settings/_webhook_settings.html.erb`
- Test: `test/unit/settings_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/settings_test.rb
require File.expand_path("../test_helper", __dir__)

class SettingsTest < ActiveSupport::TestCase
  test "plugin settings include execution and retention" do
    settings = Setting.plugin_redmine_webhook_plugin
    assert settings.key?("execution_mode")
    assert settings.key?("retention_days_success")
    assert settings.key?("retention_days_failed")
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/settings_test.rb -v'
```


Expected: FAIL - settings missing

**Step 3: Write minimal implementation**

```ruby
# init.rb
Redmine::Plugin.register :redmine_webhook_plugin do
  name "Redmine Webhook Plugin"
  author "Redmine Webhook Plugin Contributors"
  description "Outbound webhooks for issues and time entries (internal)"
  version "0.0.1"
  requires_redmine version_or_higher: "5.1.1"

  settings partial: "settings/webhook_settings", default: {
    "execution_mode" => "auto",
    "retention_days_success" => "7",
    "retention_days_failed" => "7",
    "deliveries_paused" => "0"
  }
end
```

```erb
<!-- app/views/settings/_webhook_settings.html.erb -->
<p>
  <label><%= l(:label_execution_mode) %></label>
  <%= select_tag "settings[execution_mode]", options_for_select([["auto", "auto"], ["activejob", "activejob"], ["db_runner", "db_runner"]], @settings["execution_mode"]) %>
</p>
<p>
  <label><%= l(:label_retention_success_days) %></label>
  <%= text_field_tag "settings[retention_days_success]", @settings["retention_days_success"] %>
</p>
<p>
  <label><%= l(:label_retention_failed_days) %></label>
  <%= text_field_tag "settings[retention_days_failed]", @settings["retention_days_failed"] %>
</p>
<p>
  <label><%= l(:label_deliveries_paused) %></label>
  <%= check_box_tag "settings[deliveries_paused]", "1", @settings["deliveries_paused"] == "1" %>
</p>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/settings_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/settings_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/settings_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add init.rb app/views/settings/_webhook_settings.html.erb test/unit/settings_test.rb
git commit -m "feat(final): add plugin settings"
```

---

## Task 11: Localization (Logs UI)

**Files:**
- Modify: `config/locales/en.yml`
- Test: `test/unit/localization_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/localization_test.rb - add to existing file
class LocalizationTest < ActiveSupport::TestCase
  test "delivery log locale keys exist" do
    assert_equal "Deliveries", I18n.t(:label_webhook_deliveries)
    assert_equal "Delivery", I18n.t(:label_webhook_delivery)
    assert_equal "Event ID", I18n.t(:label_event_id)
    assert_equal "HTTP Status", I18n.t(:label_http_status)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/localization_test.rb -v'
```


Expected: FAIL with missing translations

**Step 3: Write minimal implementation**

```yaml
# config/locales/en.yml - add keys
  label_webhook_deliveries: "Deliveries"
  label_webhook_delivery: "Delivery"
  label_webhook_endpoint: "Endpoint"
  label_event_type: "Event Type"
  label_event_id: "Event ID"
  label_http_status: "HTTP Status"
  label_status: "Status"
  label_payload: "Payload"
  label_api_key_fingerprint: "API Key Fingerprint"
  label_response_excerpt: "Response Excerpt"
  label_replay_selected: "Replay Selected"
  notice_webhook_delivery_replayed: "Delivery replayed"
  notice_webhook_bulk_replay: "Replayed %{count} deliveries"
  label_execution_mode: "Execution Mode"
  label_retention_success_days: "Retention Days (Success)"
  label_retention_failed_days: "Retention Days (Failed)"
  label_deliveries_paused: "Pause Deliveries"
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/localization_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/localization_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/localization_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 2 tests, 0 failures

**Step 6: Commit**

```bash
git add config/locales/en.yml test/unit/localization_test.rb
git commit -m "feat(final): add delivery log localization"
```

---

## Task 12: Final Phase Tests

**Step 1: Run full plugin tests**

Run:
```bash
# Primary version
VERSION=5.1.0 tools/test/run-test.sh

# Also verify on other versions
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
```


Expected: All tests pass

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat(final): complete delivery logs and replay features"
```

---

## Acceptance Criteria

- [ ] Admin can view delivery logs with filters and search
- [ ] Admin can replay single or bulk deliveries
- [ ] CSV export works for current filters
- [ ] Retention purge cleans old records
- [ ] Settings are configurable
- [ ] Logs UI labels localized
- [ ] All tests pass

---

## Execution Handoff

Plan complete and saved to `docs/plans/phase-final.md`. Two execution options:

1. Subagent-Driven (this session) - dispatch a fresh subagent per task, review between tasks
2. Parallel Session (separate) - open new session with @superpowers:executing-plans