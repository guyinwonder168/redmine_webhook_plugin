# Workstream A: Admin UI (Endpoints CRUD) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provide an admin UI to list, create, edit, delete, toggle, and test webhook endpoints.

**Architecture:** Use an admin-scoped controller (`Admin::WebhookEndpointsController`) with standard CRUD actions, a shared form partial, and a small set of helper methods to serialize form fields into the `RedmineWebhookPlugin::Webhook::Endpoint` model. UI is rendered in the admin layout and uses Redmine menu integration and i18n keys.

**Tech Stack:** Ruby/Rails, Redmine plugin API, ActiveRecord, Minitest

**Depends on:** P0 complete (RedmineWebhookPlugin::Webhook::Endpoint and RedmineWebhookPlugin::Webhook::Delivery models exist)
**Parallel with:** Workstreams B, C, D

## Native Webhook Compatibility (Redmine 7.0+)

Redmine 7.0+ (trunk) introduces native webhook support. The plugin remains authoritative; when native webhooks are present, disable or bypass native delivery to prevent duplicate notifications and keep the plugin Admin UI as the source of truth.

- **Namespace**: Plugin uses `module RedmineWebhookPlugin::Webhook` for table prefix, while native defines `class Webhook < ApplicationRecord`. Use `RedmineWebhookPlugin::` for plugin code and dispatcher.
- **Redmine 5.1.x / 6.1.x**: Full Admin UI for plugin webhook management (no native webhooks)
- **Redmine 7.0+**: Detect native webhooks with `defined?(::Webhook) && ::Webhook < ApplicationRecord`, disable native delivery, and continue using the plugin Admin UI (optionally show a notice that native is disabled)

**Current implementation**: Prioritize 5.1.x - 6.1.x behavior while adding 7.0+ detection to disable native delivery.

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

## Task 1: Routes and Controller Skeleton

**Files:**
- Create: `config/routes.rb`
- Create: `app/controllers/admin/webhook_endpoints_controller.rb`
- Test: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb
require File.expand_path("../../test_helper", __dir__)

class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    @admin = User.find(1)
    @non_admin = User.find(2)
  end

  test "admin can access index" do
    @request.session[:user_id] = @admin.id
    get :index

    assert_response :success
    assert_template :index
  end

  test "non-admin cannot access index" do
    @request.session[:user_id] = @non_admin.id
    get :index

    assert_response 403
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with "uninitialized constant Admin::WebhookEndpointsController" or routing error

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_endpoints
  end
end
```

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"

  def index
    @endpoints = RedmineWebhookPlugin::Webhook::Endpoint.order(:name)
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 2 tests, 0 failures

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/webhook_endpoints_controller.rb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add admin routes and controller skeleton"
```

---

## Task 2: Index View

**Files:**
- Create: `app/views/admin/webhook_endpoints/index.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

  test "index renders table and actions" do
    @request.session[:user_id] = @admin.id
    RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")

    get :index

    assert_select "table.webhook-endpoints"
    assert_select "th", text: "Name"
    assert_select "th", text: "URL"
    assert_select "th", text: "Enabled"
    assert_select "th", text: "Actions"
    assert_select "a", text: "New Endpoint"
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing template or selectors

**Step 3: Write minimal implementation**

```erb
<!-- app/views/admin/webhook_endpoints/index.html.erb -->
<h2><%= l(:label_webhook_endpoints) %></h2>

<div class="contextual">
  <%= link_to l(:label_webhook_endpoint_new), new_admin_webhook_endpoint_path, class: "icon icon-add" %>
</div>

<table class="list webhook-endpoints">
  <thead>
    <tr>
      <th><%= l(:field_name) %></th>
      <th><%= l(:field_url) %></th>
      <th><%= l(:field_enabled) %></th>
      <th><%= l(:label_action) %></th>
    </tr>
  </thead>
  <tbody>
    <% @endpoints.each do |endpoint| %>
      <tr>
        <td><%= endpoint.name %></td>
        <td><%= endpoint.url %></td>
        <td><%= endpoint.enabled? ? l(:label_yes) : l(:label_no) %></td>
        <td>
          <%= link_to l(:button_edit), edit_admin_webhook_endpoint_path(endpoint), class: "icon icon-edit" %>
          <%= link_to l(:button_delete), admin_webhook_endpoint_path(endpoint),
                      method: :delete, data: { confirm: l(:text_are_you_sure) }, class: "icon icon-del" %>
        </td>
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 3 tests, 0 failures

**Step 6: Commit**

```bash
git add app/views/admin/webhook_endpoints/index.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add webhook endpoints index view"
```

---

## Task 3: New Action and Form Partial (Base Fields)

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Create: `app/views/admin/webhook_endpoints/new.html.erb`
- Create: `app/views/admin/webhook_endpoints/_form.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

  test "new renders form with base fields" do
    @request.session[:user_id] = @admin.id

    get :new

    assert_response :success
    assert_select "form"
    assert_select "input[name='webhook_endpoint[name]']"
    assert_select "input[name='webhook_endpoint[url]']"
    assert_select "input[name='webhook_endpoint[enabled]']"
    assert_select "select[name='webhook_endpoint[payload_mode]']"
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing template or selectors

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"

  def index
    @endpoints = RedmineWebhookPlugin::Webhook::Endpoint.order(:name)
  end

  def new
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/new.html.erb -->
<h2><%= l(:label_webhook_endpoint_new) %></h2>

<%= labelled_form_for :webhook_endpoint, @endpoint, url: admin_webhook_endpoints_path do |f| %>
  <%= render partial: "form", locals: { f: f, endpoint: @endpoint } %>
  <p><%= submit_tag l(:button_save) %></p>
<% end %>
```

```erb
<!-- app/views/admin/webhook_endpoints/_form.html.erb -->
<%= error_messages_for 'webhook_endpoint' %>

<div class="box tabular">
  <p><%= f.text_field :name, size: 60, required: true %></p>
  <p><%= f.text_field :url, size: 60, required: true %></p>
  <p><%= f.check_box :enabled %></p>
  <p>
    <%= f.select :payload_mode, [[l(:label_payload_minimal), "minimal"], [l(:label_payload_full), "full"]], {}, label: :field_payload_mode %>
  </p>
</div>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 4 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/new.html.erb app/views/admin/webhook_endpoints/_form.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add new action and base form fields"
```

---

## Task 4: Create Action and Strong Params (Base Fields)

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

  test "create persists endpoint and redirects" do
    @request.session[:user_id] = @admin.id

    assert_difference "RedmineWebhookPlugin::Webhook::Endpoint.count", 1 do
      post :create, params: {
        webhook_endpoint: {
          name: "Create Test",
          url: "https://example.com",
          enabled: "1",
          payload_mode: "minimal"
        }
      }
    end

    assert_redirected_to admin_webhook_endpoints_path
    assert_equal "Create Test", RedmineWebhookPlugin::Webhook::Endpoint.last.name
  end

  test "create re-renders form on validation error" do
    @request.session[:user_id] = @admin.id

    post :create, params: { webhook_endpoint: { name: "", url: "" } }

    assert_response :success
    assert_template :new
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing create action

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"

  def index
    @endpoints = RedmineWebhookPlugin::Webhook::Endpoint.order(:name)
  end

  def new
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
  end

  def create
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(endpoint_params)

    if @endpoint.save
      flash[:notice] = l(:notice_webhook_endpoint_created)
      redirect_to admin_webhook_endpoints_path
    else
      render :new
    end
  end

  private

  def endpoint_params
    params.require(:webhook_endpoint).permit(
      :name, :url, :enabled, :payload_mode
    )
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 6 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add create action with strong params"
```

---

## Task 5: Form Fields - User and Projects

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `app/views/admin/webhook_endpoints/_form.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

  test "form includes webhook user and project selectors" do
    @request.session[:user_id] = @admin.id

    get :new

    assert_select "select[name='webhook_endpoint[webhook_user_id]']"
    assert_select "select[name='webhook_endpoint[project_ids][]']"
    assert_select "em", text: "Empty = all projects"
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing selectors

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb - add helper
class Admin::WebhookEndpointsController < AdminController
  layout "admin"

  def index
    @endpoints = RedmineWebhookPlugin::Webhook::Endpoint.order(:name)
  end

  def new
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new
    load_form_collections
  end

  def create
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(endpoint_params)
    apply_form_config(@endpoint)

    if @endpoint.save
      flash[:notice] = l(:notice_webhook_endpoint_created)
      redirect_to admin_webhook_endpoints_path
    else
      load_form_collections
      render :new
    end
  end

  private

  def load_form_collections
    @users = User.active.order(:lastname, :firstname)
    @projects = Project.active.order(:name)
  end

  def apply_form_config(endpoint)
    project_ids = Array(params[:webhook_endpoint][:project_ids]).reject(&:blank?).map(&:to_i)
    endpoint.project_ids_array = project_ids
  end

  def endpoint_params
    params.require(:webhook_endpoint).permit(
      :name, :url, :enabled, :payload_mode, :webhook_user_id,
      project_ids: []
    )
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/_form.html.erb - add to form -->
<p>
  <%= f.select :webhook_user_id,
      options_from_collection_for_select(@users, :id, :name, endpoint.webhook_user_id),
      { include_blank: true, label: :field_webhook_user } %>
</p>

<p>
  <%= label_tag "webhook_endpoint_project_ids", l(:field_project) %>
  <%= select_tag "webhook_endpoint[project_ids][]",
      options_from_collection_for_select(@projects, :id, :name, endpoint.project_ids_array),
      multiple: true, id: "webhook_endpoint_project_ids" %>
  <br><em><%= l(:text_webhook_projects_hint) %></em>
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 7 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/_form.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add webhook user and project selectors"
```

---

## Task 6: Events Config Checkboxes and Serialization

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `app/views/admin/webhook_endpoints/_form.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing checkboxes or events_config not set

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb - add events_config handling
class Admin::WebhookEndpointsController < AdminController
  # ... existing code ...

  private

  def apply_form_config(endpoint)
    project_ids = Array(params[:webhook_endpoint][:project_ids]).reject(&:blank?).map(&:to_i)
    endpoint.project_ids_array = project_ids
    endpoint.events_config = extract_events_config(params[:events])
  end

  def extract_events_config(events_param)
    return {} if events_param.nil?

    events_param.each_with_object({}) do |(resource, actions), memo|
      memo[resource.to_s] = {}
      actions.each do |action, value|
        memo[resource.to_s][action.to_s] = value.to_s == "1"
      end
    end
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/_form.html.erb - add event checkboxes -->
<div class="box">
  <fieldset>
    <legend><%= l(:label_webhook_events) %></legend>
    <p><strong><%= l(:label_issue_plural) %></strong></p>
    <label><input type="checkbox" name="events[issue][created]" value="1"> <%= l(:label_webhook_event_created) %></label>
    <label><input type="checkbox" name="events[issue][updated]" value="1"> <%= l(:label_webhook_event_updated) %></label>
    <label><input type="checkbox" name="events[issue][deleted]" value="1"> <%= l(:label_webhook_event_deleted) %></label>

    <p><strong><%= l(:label_time_entry_plural) %></strong></p>
    <label><input type="checkbox" name="events[time_entry][created]" value="1"> <%= l(:label_webhook_event_created) %></label>
    <label><input type="checkbox" name="events[time_entry][updated]" value="1"> <%= l(:label_webhook_event_updated) %></label>
    <label><input type="checkbox" name="events[time_entry][deleted]" value="1"> <%= l(:label_webhook_event_deleted) %></label>
  </fieldset>
</div>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 9 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/_form.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add events config form and serialization"
```

---

## Task 7: Retry Config Fields and Serialization

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `app/views/admin/webhook_endpoints/_form.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing selectors or retry_config not set

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb - extend apply_form_config
class Admin::WebhookEndpointsController < AdminController
  # ... existing code ...

  private

  def apply_form_config(endpoint)
    project_ids = Array(params[:webhook_endpoint][:project_ids]).reject(&:blank?).map(&:to_i)
    endpoint.project_ids_array = project_ids
    endpoint.events_config = extract_events_config(params[:events])
    endpoint.retry_config = extract_retry_config(params[:retry])
  end

  def extract_retry_config(retry_param)
    return {} if retry_param.nil?

    {
      "max_attempts" => retry_param[:max_attempts].to_i,
      "base_delay" => retry_param[:base_delay].to_i,
      "max_delay" => retry_param[:max_delay].to_i
    }
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/_form.html.erb - add retry fields -->
<div class="box">
  <fieldset>
    <legend><%= l(:label_webhook_retry) %></legend>
    <p><%= label_tag "retry_max_attempts", l(:field_retry_max_attempts) %><br>
      <input type="number" name="retry[max_attempts]" value="5" min="1"></p>
    <p><%= label_tag "retry_base_delay", l(:field_retry_base_delay) %><br>
      <input type="number" name="retry[base_delay]" value="60" min="1"></p>
    <p><%= label_tag "retry_max_delay", l(:field_retry_max_delay) %><br>
      <input type="number" name="retry[max_delay]" value="3600" min="1"></p>
  </fieldset>

  <fieldset>
    <legend><%= l(:label_webhook_request_options) %></legend>
    <p><%= label_tag "webhook_endpoint_timeout", l(:field_timeout) %><br>
      <%= number_field_tag "webhook_endpoint[timeout]", endpoint.timeout || 30, min: 1 %></p>
    <p><%= label_tag "webhook_endpoint_ssl_verify", l(:field_ssl_verify) %><br>
      <%= check_box_tag "webhook_endpoint[ssl_verify]", "1", endpoint.ssl_verify != false %></p>
  </fieldset>
</div>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 11 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/_form.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add retry and request options fields"
```

---

## Task 8: Edit and Update Actions

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Create: `app/views/admin/webhook_endpoints/edit.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing edit/update

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update]

  # ... existing actions ...

  def edit
    load_form_collections
  end

  def update
    @endpoint.assign_attributes(endpoint_params)
    apply_form_config(@endpoint)

    if @endpoint.save
      flash[:notice] = l(:notice_webhook_endpoint_updated)
      redirect_to admin_webhook_endpoints_path
    else
      load_form_collections
      render :edit
    end
  end

  private

  def find_endpoint
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.find(params[:id])
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/edit.html.erb -->
<h2><%= l(:label_webhook_endpoint_edit) %></h2>

<%= labelled_form_for :webhook_endpoint, @endpoint, url: admin_webhook_endpoint_path(@endpoint), html: { method: :patch } do |f| %>
  <%= render partial: "form", locals: { f: f, endpoint: @endpoint } %>
  <p><%= submit_tag l(:button_save) %></p>
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 13 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/edit.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add edit/update actions"
```

---

## Task 9: Destroy Action with Delivery Marking

**Files:**
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Expected: FAIL with missing destroy**

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update, :destroy]

  # ... existing actions ...

  def destroy
    affected = @endpoint.deliveries.update_all(
      status: RedmineWebhookPlugin::Webhook::Delivery::ENDPOINT_DELETED,
      endpoint_id: nil
    )

    @endpoint.destroy
    flash[:notice] = l(:notice_webhook_endpoint_deleted, count: affected)
    redirect_to admin_webhook_endpoints_path
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
 -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
 -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 14 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add destroy action with delivery marking"
```

---

**Status:** ✅ **Complete** (Verified 2025-12-29)

**Summary:** Task 9 destroy action with delivery marking was already implemented. Implementation verified across all three Redmine versions (5.1.0, 5.1.10, 6.1.0). Tests passing: 53 runs, 227 assertions on 6.1.0.

**Files Verified:**
- `app/controllers/admin/webhook_endpoints_controller.rb` (lines 44-53) - Destroy action implemented
- `test/functional/admin/webhook_endpoints_controller_test.rb` (lines 139-157) - Tests present and passing
- `app/views/admin/webhook_endpoints/index.html.erb` (lines 26-27) - Delete link with confirmation
- `config/locales/en.yml` (line 23) - Localization key with count interpolation

**Test Results:**
```
test_destroy_deletes_endpoint_and_marks_deliveries
✅ 1 runs, 5 assertions, 0 failures, 0 errors, 0 skips
```

**Implementation Features:**
- Uses `update_all` for efficient bulk delivery updates
- Marks deliveries with `ENDPOINT_DELETED` status
- Sets `endpoint_id` to nil to prevent cascade delete
- Displays flash notice with affected delivery count
- Properly redirects to admin endpoints index
- All tests pass on Redmine 5.1.0, 5.1.10, and 6.1.0

**Step 2: Run test to verify it fails**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing destroy

**Step 3: Write minimal implementation**

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update, :destroy]

  # ... existing actions ...

  def destroy
    affected = @endpoint.deliveries.update_all(
      status: RedmineWebhookPlugin::Webhook::Delivery::ENDPOINT_DELETED,
      endpoint_id: nil
    )

    @endpoint.destroy
    flash[:notice] = l(:notice_webhook_endpoint_deleted, count: affected)
    redirect_to admin_webhook_endpoints_path
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 14 tests, 0 failures

**Step 6: Commit**

```bash
git add app/controllers/admin/webhook_endpoints_controller.rb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add destroy action with delivery marking"
```

---

## Task 10: Toggle Enable/Disable Action

**Status:** ✅ **Complete** (Verified 2025-12-29)

**Summary:** Task 10 toggle enable/disable action was already implemented. Implementation verified across all three Redmine versions. Toggle action uses `@endpoint.toggle!(:enabled)` pattern with proper flash messages and redirect.

**Files Verified:**
- `app/controllers/admin/webhook_endpoints_controller.rb` (lines 55-59) - Toggle action implemented
- `app/controllers/admin/webhook_endpoints_controller.rb` (line 3) - `before_action :find_endpoint, only: [:edit, :update, :destroy, :toggle]`
- `test/functional/admin/webhook_endpoints_controller_test.rb` (lines 159-179) - Two toggle tests present and passing
- `app/views/admin/webhook_endpoints/index.html.erb` (lines 24-25) - Toggle link with PATCH method
- `config/locales/en.yml` (line 24) - `notice_webhook_endpoint_toggled` localization key

**Test Results:**
```
test_toggle_flips_enabled_flag
✅ Pass: Flips enabled from true to false

test_toggle_can_enable_disabled_endpoint
✅ Pass: Flips enabled from false to true
```

**Implementation Features:**
- Uses `@endpoint.toggle!(:enabled)` for clean implementation
- Routes configured with `post :toggle, on: :member`
- Flash message confirms toggle action
- Redirects to admin endpoints index
- Both enable/disable scenarios tested
- All tests pass on all Redmine versions (5.1.0, 5.1.10, 6.1.0)

---

**Remaining Tasks in Workstream A:**
- Task 12: Webhook User Validation and API Key Warning
- Task 13: Menu Integration
- Task 14: Localization

**Progress:** 11/14 tasks complete (79%)

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

  test "toggle flips enabled flag" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Toggle", url: "https://example.com", enabled: true)

    post :toggle, params: { id: endpoint.id }

    assert_redirected_to admin_webhook_endpoints_path
    assert_equal false, endpoint.reload.enabled
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing route or action

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_endpoints do
      post :toggle, on: :member
    end
  end
end
```

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update, :destroy, :toggle]

  # ... existing actions ...

  def toggle
    @endpoint.update!(enabled: !@endpoint.enabled?)
    flash[:notice] = l(:notice_webhook_endpoint_toggled)
    redirect_to admin_webhook_endpoints_path
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/index.html.erb - add toggle link -->
<%= link_to l(:label_toggle), toggle_admin_webhook_endpoint_path(endpoint),
            method: :post, class: "icon icon-toggle" %>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 15 tests, 0 failures

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/index.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add toggle action for endpoints"
```

---

## Task 11: Send Test Action ✅ COMPLETE (Verified 2025-12-29)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `app/views/admin/webhook_endpoints/index.html.erb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

  test "test action creates a test delivery" do
    @request.session[:user_id] = @admin.id
    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.create!(name: "Test", url: "https://example.com")

    assert_difference "RedmineWebhookPlugin::Webhook::Delivery.count", 1 do
      post :test, params: { id: endpoint.id }
    end

    delivery = RedmineWebhookPlugin::Webhook::Delivery.last
    assert_equal true, delivery.is_test
    assert_equal endpoint.id, delivery.endpoint_id
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```


Expected: FAIL with missing route/action

**Step 3: Write minimal implementation**

```ruby
# config/routes.rb
RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_endpoints do
      post :toggle, on: :member
      post :test, on: :member
    end
  end
end
```

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb
class Admin::WebhookEndpointsController < AdminController
  layout "admin"
  before_action :find_endpoint, only: [:edit, :update, :destroy, :toggle, :test]

  # ... existing actions ...

  def test
    RedmineWebhookPlugin::Webhook::Delivery.create!(
      endpoint_id: @endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: "test",
      action: "test",
      status: RedmineWebhookPlugin::Webhook::Delivery::PENDING,
      payload: { message: "Test delivery" }.to_json,
      endpoint_url: @endpoint.url,
      is_test: true
    )

    flash[:notice] = l(:notice_webhook_test_queued)
    redirect_to admin_webhook_endpoints_path
  end
end
```

```erb
<!-- app/views/admin/webhook_endpoints/index.html.erb - add test link -->
<%= link_to l(:label_webhook_send_test), test_admin_webhook_endpoint_path(endpoint),
            method: :post, class: "icon icon-test" %>
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/functional/admin/webhook_endpoints_controller_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 16 tests, 0 failures

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/webhook_endpoints_controller.rb app/views/admin/webhook_endpoints/index.html.erb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): add test action for endpoints"
```

**Verification (2025-12-29):**
- ✅ All 3 tests passing on Redmine 5.1.0 (17 runs, 65 assertions)
- ✅ All 3 tests passing on Redmine 5.1.10 (17 runs, 65 assertions)
- ✅ All 3 tests passing on Redmine 6.1.0 (17 runs, 67 assertions)
- Test action creates delivery with is_test=true
- Test action uses synthetic payload (event_type='test', action='test')
- Test action sets status to PENDING
- Test action requires admin access
- Test link added to index view

**Verification (2026-01-04):**
- ✅ Redmine 6.1.0 plugin tests passing (60 runs, 257 assertions)
- ✅ Plugin migrations skip existing tables via table_exists? guards

---

## Task 12: Webhook User Validation and API Key Warning

**Files:**
- Modify: `app/models/webhook/endpoint.rb`
- Modify: `app/controllers/admin/webhook_endpoints_controller.rb`
- Modify: `test/unit/webhook/endpoint_test.rb`
- Modify: `test/functional/admin/webhook_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/unit/webhook/endpoint_test.rb - add to existing file
class RedmineWebhookPlugin::Webhook::EndpointTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "validates webhook_user_id must be active" do
    inactive = User.create!(login: "inactive", firstname: "Inactive", lastname: "User", status: User::STATUS_LOCKED)

    endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(name: "Test", url: "https://example.com", webhook_user_id: inactive.id)

    assert_not endpoint.valid?
    assert_includes endpoint.errors[:webhook_user_id], "must be an active user"
  end
end
```

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - add to existing file
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
  # ... existing setup ...

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

    assert_equal "warn", flash[:warning]&.downcase
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```


Expected: FAIL with missing validation

**Step 3: Write minimal implementation**

```ruby
# app/models/webhook/endpoint.rb - add validation
class RedmineWebhookPlugin::Webhook::Endpoint < ActiveRecord::Base
  # ... existing code ...

  validate :webhook_user_must_be_active

  private

  def webhook_user_must_be_active
    return if webhook_user_id.blank?

    user = User.find_by(id: webhook_user_id)
    if user.nil? || !user.active?
      errors.add(:webhook_user_id, "must be an active user")
    end
  end
end
```

```ruby
# app/controllers/admin/webhook_endpoints_controller.rb - add warning
class Admin::WebhookEndpointsController < AdminController
  # ... existing code ...

  def create
    @endpoint = RedmineWebhookPlugin::Webhook::Endpoint.new(endpoint_params)
    apply_form_config(@endpoint)

    if @endpoint.save
      set_api_key_warning(@endpoint)
      flash[:notice] = l(:notice_webhook_endpoint_created)
      redirect_to admin_webhook_endpoints_path
    else
      load_form_collections
      render :new
    end
  end

  private

  def set_api_key_warning(endpoint)
    return if endpoint.webhook_user_id.blank?

    token = Token.find_by(user_id: endpoint.webhook_user_id, action: "api")
    flash[:warning] = l(:warning_webhook_user_no_api_key) if token.nil?
  end
end
```

```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb - adjust warning assertion
assert_equal l(:warning_webhook_user_no_api_key), flash[:warning]
```

**Step 4: Run test to verify it passes**

Run:
```bash
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook/endpoint_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - validations test passes

**Step 6: Commit**

```bash
git add app/models/webhook/endpoint.rb app/controllers/admin/webhook_endpoints_controller.rb test/unit/webhook/endpoint_test.rb test/functional/admin/webhook_endpoints_controller_test.rb
git commit -m "feat(ws-a): validate webhook_user and warn on missing API key"
```

---

## Task 13: Menu Integration

**Files:**
- Modify: `init.rb`
- Test: `test/unit/admin_menu_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/admin_menu_test.rb
require File.expand_path("../test_helper", __dir__)

class AdminMenuTest < ActiveSupport::TestCase
  test "admin menu includes webhooks item" do
    items = Redmine::MenuManager.items(:admin_menu).map(&:name)
    assert_includes items, :webhooks
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/admin_menu_test.rb -v'
```


Expected: FAIL with missing menu item

**Step 3: Write minimal implementation**

```ruby
# init.rb - add menu entry
Redmine::Plugin.register :redmine_webhook_plugin do
  name "Redmine Webhook Plugin"
  author "Redmine Webhook Plugin Contributors"
  description "Outbound webhooks for issues and time entries (internal)"
  version "0.0.1"
  requires_redmine version_or_higher: "5.1.1"

  menu :admin_menu, :webhooks, { controller: "admin/webhook_endpoints", action: "index" },
       caption: :label_webhook_endpoints, html: { class: "icon icon-webhook" }
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
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/admin_menu_test.rb -v'
```

**Step 5: Cross-version verification (5.1.10 and 6.1.0)**

```bash
# 5.1.10
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.10:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:5.1.10 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/admin_menu_test.rb -v'

# 6.1.0
podman run --rm -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/6.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle -e RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test \
  redmine-dev:6.1.0 \
  bash -lc 'cd /redmine && bundle exec ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/admin_menu_test.rb -v'
```

Expected: PASS on all versions


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add init.rb test/unit/admin_menu_test.rb
git commit -m "feat(ws-a): add admin menu entry for webhooks"
```

---

## Task 14: Localization

**Files:**
- Create: `config/locales/en.yml`
- Test: `test/unit/localization_test.rb`

**Step 1: Write the failing test**

```ruby
# test/unit/localization_test.rb
require File.expand_path("../test_helper", __dir__)

class LocalizationTest < ActiveSupport::TestCase
  test "webhook locale keys exist" do
    assert_equal "Webhook Endpoints", I18n.t(:label_webhook_endpoints)
    assert_equal "New Endpoint", I18n.t(:label_webhook_endpoint_new)
    assert_equal "Edit Endpoint", I18n.t(:label_webhook_endpoint_edit)
    assert_equal "Payload Mode", I18n.t(:field_payload_mode)
    assert_equal "Retry Policy", I18n.t(:label_webhook_retry)
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
# config/locales/en.yml
en:
  label_webhook_endpoints: "Webhook Endpoints"
  label_webhook_endpoint_new: "New Endpoint"
  label_webhook_endpoint_edit: "Edit Endpoint"
  label_webhook_events: "Events"
  label_webhook_event_created: "Created"
  label_webhook_event_updated: "Updated"
  label_webhook_event_deleted: "Deleted"
  label_webhook_retry: "Retry Policy"
  label_webhook_request_options: "Request Options"
  label_webhook_send_test: "Send Test"
  label_payload_minimal: "Minimal"
  label_payload_full: "Full"
  field_payload_mode: "Payload Mode"
  field_webhook_user: "Webhook User"
  field_retry_max_attempts: "Max Attempts"
  field_retry_base_delay: "Base Delay (seconds)"
  field_retry_max_delay: "Max Delay (seconds)"
  field_ssl_verify: "Verify SSL"
  notice_webhook_endpoint_created: "Webhook endpoint created"
  notice_webhook_endpoint_updated: "Webhook endpoint updated"
  notice_webhook_endpoint_deleted: "Webhook endpoint deleted (affected deliveries: %{count})"
  notice_webhook_endpoint_toggled: "Webhook endpoint toggled"
  notice_webhook_test_queued: "Test delivery queued"
  warning_webhook_user_no_api_key: "Webhook user has no API key"
  text_webhook_projects_hint: "Empty = all projects"
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


Expected: PASS - 1 test, 0 failures

**Step 6: Commit**

```bash
git add config/locales/en.yml test/unit/localization_test.rb
git commit -m "feat(ws-a): add webhook admin UI localization"
```

---

## Task 15: Run All Workstream A Tests

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
git commit -m "feat(ws-a): complete admin UI for webhook endpoints"
```

---

## Acceptance Criteria

- [ ] Admin can list, create, edit, delete endpoints
- [ ] Endpoint form saves user, projects, events, retry config
- [x] Test button creates a test delivery (Task 11)
- [x] Enable/disable toggle works (Task 10)
- [ ] Non-admins cannot access pages
- [ ] Menu entry appears in Admin menu
- [x] All unit/functional tests pass (Verified 2025-12-29: 17 runs, 65 assertions on 5.1.0/5.1.10, 67 assertions on 6.1.0)

---

## Execution Handoff

Plan complete and saved to `docs/plans/ws-a-admin-ui.md`. Two execution options:

1. Subagent-Driven (this session) - dispatch a fresh subagent per task, review between tasks
2. Parallel Session (separate) - open new session with @superpowers:executing-plans