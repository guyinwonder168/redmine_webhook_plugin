# Plan Review: ws-a-admin-ui.md

**Reviewer:** Sisyphus (AI Agent)
**Date:** 2025-12-26
**Plan:** Workstream A: Admin UI (Endpoints CRUD) Implementation Plan
**Review Type:** Sanity Check against Redmine conventions and codebase

---

## Summary

The plan is **mostly sound** with 4 issues requiring adjustment before execution. The database schema supports all planned features.

| Category | Status |
|----------|--------|
| Controller Inheritance | ✅ Valid (AdminController exists) |
| Model Attributes | ✅ All attributes exist in migrations |
| Test Base Class | ⚠️ Should use Redmine::ControllerTest |
| Form Patterns | ⚠️ URL handling needs adjustment |
| Delivery.is_test | ✅ Exists in schema |
| i18n Keys | ⚠️ Some Redmine core keys may differ |

---

## Issue 1: Test Base Class (MEDIUM)

**Location:** All test files (Tasks 1-12)

**Problem:** Plan uses `ActionController::TestCase`:
```ruby
class Admin::WebhookEndpointsControllerTest < ActionController::TestCase
```

**Redmine Convention:** Use `Redmine::ControllerTest` which provides:
- `log_user(user)` helper
- `with_settings()` helper
- Better Redmine integration

**Fix:**
```ruby
class Admin::WebhookEndpointsControllerTest < Redmine::ControllerTest
```

**Impact:** Low - tests will work either way, but Redmine helpers won't be available.

---

## Issue 2: Form Partial URL Handling (HIGH)

**Location:** Task 3 (_form.html.erb), Task 8 (edit.html.erb)

**Problem:** The form partial hardcodes the URL for create:
```erb
<%= form_with model: endpoint, url: admin_webhook_endpoints_path, method: :post do |f| %>
```

When reused for edit, this will POST to the wrong URL.

**Redmine Convention:** Parent views wrap forms with correct URLs:

**new.html.erb:**
```erb
<%= labelled_form_for :webhook_endpoint, @endpoint, url: admin_webhook_endpoints_path do |f| %>
  <%= render partial: "form", locals: { f: f } %>
<% end %>
```

**edit.html.erb:**
```erb
<%= labelled_form_for :webhook_endpoint, @endpoint, url: admin_webhook_endpoint_path(@endpoint), html: { method: :patch } do |f| %>
  <%= render partial: "form", locals: { f: f } %>
<% end %>
```

**_form.html.erb:** (remove form wrapper, receive `f` from parent)
```erb
<div class="box">
  <p><%= f.text_field :name, size: 60, required: true %></p>
  <!-- ... rest of fields ... -->
</div>
<p><%= submit_tag l(:button_save) %></p>
```

**Impact:** High - edit form will break without this fix.

---

## Issue 3: User/Project Selectors in Form (MEDIUM)

**Location:** Task 5 (_form.html.erb)

**Problem:** Plan mixes form builder fields (`f.text_field`) with standalone helpers (`select_tag`):
```erb
<%= select_tag "webhook_endpoint[webhook_user_id]", ... %>
<%= select_tag "webhook_endpoint[project_ids][]", ... %>
```

This works but is inconsistent. With Redmine's pattern, use `f.select` or keep `select_tag` but ensure the field names match what `endpoint_params` expects.

**Recommendation:** Use consistent pattern:
```erb
<%= f.select :webhook_user_id, options_from_collection_for_select(@users, :id, :name, f.object.webhook_user_id), include_blank: true %>
```

**Impact:** Medium - current approach works but inconsistent.

---

## Issue 4: i18n Key Naming (LOW)

**Location:** Task 14 (locales/en.yml)

**Problem:** Some keys may conflict with or should align with Redmine core:
- `:field_name` - Redmine already has this
- `:field_url` - Redmine may have this
- `:label_action` - Redmine uses `:label_actions` (plural)

**Recommendation:** Check Redmine's `config/locales/en.yml` for existing keys before defining new ones. Prefix plugin-specific keys:
```yaml
label_webhook_endpoint_name: "Endpoint Name"  # Instead of reusing :field_name
```

**Impact:** Low - may cause unexpected translations if keys collide.

---

## Verified: Schema Matches Plan

The following attributes exist and match plan assumptions:

**RedmineWebhookPlugin::Webhook::Endpoint:**
- ✅ `name` (string, required, unique)
- ✅ `url` (text, required)
- ✅ `enabled` (boolean, default true)
- ✅ `webhook_user_id` (integer, optional)
- ✅ `payload_mode` (string, default "minimal")
- ✅ `events_config` (text/JSON)
- ✅ `project_ids` (text/JSON)
- ✅ `retry_config` (text/JSON)
- ✅ `timeout` (integer, default 30)
- ✅ `ssl_verify` (boolean, default true)

**RedmineWebhookPlugin::Webhook::Delivery:**
- ✅ `is_test` (boolean, default false)
- ✅ `payload` (text)
- ✅ `endpoint_url` (text)
- ✅ All status constants defined in model

---

## Verified: Controller Pattern

The plan's approach of inheriting from `AdminController` is valid:
- `AdminController` exists in Redmine core
- It sets `layout 'admin'`, `before_action :require_admin`
- Plugin can safely inherit from it

---

## Recommended Adjustments Before Execution

### Must Fix (blocking):
1. **Issue 2**: Restructure form partial to receive `f` from parent views
2. Update new.html.erb and edit.html.erb to use `labelled_form_for` with correct URLs

### Should Fix (quality):
3. **Issue 1**: Change test base class to `Redmine::ControllerTest`
4. **Issue 3**: Use consistent form builder methods

### Nice to Have:
5. **Issue 4**: Review i18n keys against Redmine core

---

## Execution Recommendation

The plan can proceed with the following modifications applied during execution:

1. When implementing Task 3, use the Redmine form pattern (parent wraps form)
2. When implementing tests, use `Redmine::ControllerTest` as base
3. Cross-check i18n keys with Redmine core before Task 14

**Overall Assessment:** Plan is solid, just needs form pattern adjustment.

---

## Addendum (2026-01-04)

- ✅ Plugin migrations now skip creation when tables already exist (`table_exists?` guards for `webhook_endpoints` and `webhook_deliveries`).
- ✅ Re-run verification: Redmine 6.1.0 plugin tests pass (60 runs, 257 assertions).
- ✅ Redmine 5.1.0 and 5.1.10 logs show passing plugin tests (6 runs, 83 assertions).
- ℹ️ Dev startup update: Redmine 6.1.0 uses default password `Admin1234!` due to Rails 8 password validation; 5.1.x remains `admin/admin`.
