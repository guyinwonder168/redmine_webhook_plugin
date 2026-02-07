# Changelog

All notable changes to this project will be documented in this file.

# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed
- **chore(public): sanitize repository for open-source publication**
   - Replaced internal host/org references in docs and CI snippets with neutral placeholders.
   - Updated contributor/author text in public-facing metadata and documentation.
   - Added `redmine_webhook_plugin.wiki/` to `.gitignore` so wiki content can be published separately later.
   - Removed local-only artifacts from this working copy (`.redmine-test/`, `.bundle-cache/`, `.opencode/`, `.work/`, `logs/`, and temporary screenshot files).
- **chore(github): bootstrap open-source GitHub repository flow**
   - Added GitHub community health files and templates (`.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md`, `CODE_OF_CONDUCT.md`).
   - Added GitHub Actions workflows for CI and tag-based releases (`.github/workflows/ci.yml`, `.github/workflows/release.yml`).
   - Added Dependabot configuration (`.github/dependabot.yml`).
   - Updated installer/docs links to the public GitHub repository and release URLs.
   - Updated project license to MIT for open-source distribution.

### Fixed
 - **fix(ui): alignment and icons improvements**
    - Improved "Webhook" icon with a cleaner SVG path.
    - Added catchy "Webhook Deliveries" icon for administration menu.
    - Fixed alignment in Plugin Configuration settings by switching to standard Redmine `tabular` layout.
    - Fixed alignment in Webhook Deliveries filter by switching to standard Redmine `tabular` layout.
    - Added SVG icons for "Send Test" and "Toggle" actions in Endpoints index.
 - **fix(i18n): missing translations in delivery logs UI**
    - Added missing translation keys for delivery status values (pending, delivering, success, failed, dead, endpoint_deleted).
    - Added missing translation keys for delivery detail section headers and field labels.
    - Added missing translation keys for timestamps, response body, and payload labels.
    - Updated `app/views/admin/webhook_deliveries/show.html.erb` to use `l()` helper for all hardcoded labels.
    - Updated `app/views/admin/webhook_deliveries/index.html.erb` to translate status values in filter and table.
    - Completed translations for all languages: English, Indonesian, and Arabic.

### [2026-02-04]


 - **feat(v1.0.0): Documentation consolidation**
   - Consolidated manual UI testing into `docs/testing-guide.md` (formerly `docs/podman-testing-guide.md`)
   - Added "Manual UI Testing (Browser)" chapter with comprehensive guidance
   - Added "Webhook Test Server Overview" subsection with detailed documentation of `tools/webhook_test_server.py`
   - Updated `docs/README.md` with cross-reference to testing guide
   - Removed redundant `docs/manual_browser_testing.md` (merged into testing-guide.md)
   - Removed redundant `docs/testing.md` (was 95% identical to podman-testing-guide.md)
   - Renamed `docs/podman-testing-guide.md` to `docs/testing-guide.md` for clarity
   - Documentation now organized with clear separation:
     - `testing-guide.md`: Primary guide for all testing (Podman, browser, manual UI)
     - `README.md`: Quickstart overview (points to testing-guide.md)
     - `WIKI.md`: End-user guide (installation, configuration, admin, API)
     - `development.md`: Local dev workflow (unique content)
     - `PRD v1.0.0.md`: Product requirements (design document)
- feat(v1.0.0): Payload builder alignment (FR-11a)
  - Updated `app/services/webhook/payload_builder.rb` - changed journal to last_note in payload output
  - Updated `test/unit/webhook/payload_builder_test.rb` - changed journal to last_note assertions (4 lines)
  - Features: Journal notes now available in full mode as 'last_note' field per PRD
  - Tests: build includes last_note when journal present; build excludes last_note when not present
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (300 runs, 1086 assertions, 0 failures)
- feat(v1.0.0): DB runner batch limits (NFR-7)
  - Updated `lib/tasks/webhook.rake` - added BATCH_SIZE env var support; replaced find_each with limit(batch_size).each
  - Created `test/unit/webhook/rake_batch_test.rb` - tests for BATCH_SIZE limit and default 50
  - Features: Process max 50 deliveries per rake execution; configurable via BATCH_SIZE env var
  - Tests: process task respects BATCH_SIZE limit; process task defaults to 50 batch size
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (300 runs, 1086 assertions, 0 failures)
- feat(v1.0.0): add global delivery pause (FR-22b)
  - Updated `app/services/webhook/dispatcher.rb` - added pause check at top of dispatch
  - Updated `app/services/webhook/sender.rb` - added pause check before mark_delivering!
  - Created `test/unit/webhook/global_pause_test.rb` - tests for dispatcher and sender pause
  - Features: Global delivery pause via plugin settings; Dispatcher respects pause; Sender respects pause
  - Tests: Dispatcher does not create deliveries when paused; Sender does not send when paused
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (298 runs, 1088 assertions, 0 failures)
- feat(v1.0.0): add admin menu deliveries link and cross-link
  - Updated `init.rb` - added second admin menu entry for webhook_deliveries
  - Updated `app/views/admin/webhook_endpoints/index.html.erb` - added link to filtered deliveries per endpoint
  - Created `test/functional/admin/webhook_navigation_test.rb` - tests for admin menu link and endpoints cross-link
  - Features: Deliveries now accessible from admin menu; Endpoints index includes link to view filtered deliveries
  - Tests: admin menu includes deliveries link; endpoints index includes link to filtered deliveries
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (298 runs, 1083 assertions, 0 failures)

### Changed
- (none)

### Fixed
- (none)

## [1.0.0] - 2026-02-03

### Summary
Last Gap Implementation Plan v2 completed successfully. All PRD requirements implemented and tested across all supported Redmine versions (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev).

### Added
- feat(final): add localization for delivery logs UI
  - Updated `config/locales/en.yml` - added 13 locale keys for settings labels, delivery log labels, and notice messages
  - Updated `test/unit/localization_test.rb` - added 3 new tests (settings locale keys, delivery log locale keys, notice locale keys)
  - Keys added: label_execution_mode, label_execution_mode_auto, label_execution_mode_activejob, label_execution_mode_db_runner, label_retention_success_days, label_retention_failed_days, label_deliveries_paused, notice_webhook_delivery_replayed, notice_webhook_bulk_replay, label_event_id, label_payload, label_api_key_fingerprint, label_response_excerpt
  - Tests: settings locale keys exist; delivery log locale keys exist; notice locale keys exist
- feat(final): add plugin settings
  - Updated `init.rb` - added `settings` block with defaults (execution_mode=auto, retention_days_success=7, retention_days_failed=7, deliveries_paused=0)
  - Created `app/views/settings/_webhook_settings.html.erb` - settings form with execution mode select, retention day fields, deliveries paused checkbox
  - Created `test/unit/settings_test.rb` - 2 tests for settings keys and default values
  - Updated `app/services/webhook/execution_mode.rb` - fixed auto mode to return nil (triggers real auto-detection)
  - Features: plugin settings UI accessible from Redmine admin; execution mode selector (auto/activejob/db_runner); retention day configuration; delivery pause toggle
  - Tests: plugin settings include execution and retention; plugin settings default values
 - feat(final): add retention purge logic
  - Updated `lib/tasks/webhook.rake` - implemented `redmine:webhooks:purge` task with configurable retention periods
  - Updated `test/unit/webhook_rake_test.rb` - added 2 tests for purge logic (default retention + custom ENV retention)
  - Features: reads RETENTION_DAYS_SUCCESS and RETENTION_DAYS_FAILED from ENV (default 7 days); deletes successful deliveries older than success cutoff; deletes failed/dead deliveries older than failed cutoff; preserves pending and recent deliveries; prints purge summary with counts
  - Tests: purge removes old deliveries based on retention and preserves fresh ones; purge respects custom retention days from ENV
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (5 tests, 20 assertions, 0 failures)
- feat(final): add purge task skeleton
  - Updated `lib/tasks/webhook.rake` - added `redmine:webhooks:purge` task skeleton with :environment dependency
  - Updated `test/unit/webhook_rake_test.rb` - added `test_purge_task_is_defined` to verify task is defined
  - Features: task skeleton with placeholder message; actual purge logic to be implemented in Task 9
  - Tests: purge task is defined and accessible
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (3 tests, 4 assertions, 0 failures)
- feat(final): add CSV export for deliveries
  - Updated `app/controllers/admin/webhook_deliveries_controller.rb` - added `format.csv` handling in index action with `export_to_csv` private method
  - Updated `app/views/admin/webhook_deliveries/index.html.erb` - added CSV export link in contextual area
  - Updated `config/locales/en.yml` - added `label_export_options` localization
  - Features: exports up to 1,000 most recent deliveries; respects filters; includes headers (ID, Endpoint, Event Type, Action, Status, HTTP Status, Created At); sets proper CSV content type and filename
  - Tests: export returns CSV with correct headers; export includes delivery data; export limits to 1000 records; export respects filters; export sets correct filename; export handles empty deliveries list
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (6 tests, 1042-1044 assertions, 0 failures)

- feat(final): add pagination for deliveries index
  - Updated `app/controllers/admin/webhook_deliveries_controller.rb` - replaced `.limit(50)` with Redmine's `paginate` helper
  - Updated `app/views/admin/webhook_deliveries/index.html.erb` - added `pagination_links_full` to display pagination controls
  - Features: displays 50 deliveries per page; page parameter supported; pagination links preserve filter parameters
  - Tests: index uses pagination and assigns delivery pages; index respects per_page limit of 50; index supports page parameter; index pagination preserves filters
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (12 tests, 1004 assertions, 0 failures)
- feat(final): add bulk replay action for deliveries
  - Added `post :bulk_replay` collection route to `config/routes.rb`
  - Added `bulk_replay` action in `app/controllers/admin/webhook_deliveries_controller.rb`
  - Features: accepts array of delivery IDs via params[:ids]; resets each delivery using reset_for_replay!; enqueues DeliveryJob for each if activejob mode; displays flash notice with count of replayed deliveries; shows warning flash if no IDs provided
  - Updated `app/views/admin/webhook_deliveries/index.html.erb` - wrapped table in form; added checkbox column with "check all" toggle; added individual checkboxes for each delivery row; added "Replay Selected" submit button
  - Updated `config/locales/en.yml` - added `button_replay_selected` localization
  - Tests: bulk_replay resets multiple deliveries and enqueues jobs; bulk_replay with no IDs shows flash warning
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev (8 tests, 66 assertions, 0 failures)
- feat(final): add replay action for deliveries
  - Added `post :replay` member route to `config/routes.rb`
  - Added `replay` action in `app/controllers/admin/webhook_deliveries_controller.rb`
  - Features: resets delivery status to PENDING, clears attempt_count, http_status, delivered_at, response_body_excerpt, duration_ms, error_code; enqueues DeliveryJob if activejob mode; displays flash notice
  - Updated `app/models/redmine_webhook_plugin/webhook/delivery.rb` - enhanced `reset_for_replay!` to also clear delivered_at, response_body_excerpt, duration_ms
  - Updated `app/views/admin/webhook_deliveries/show.html.erb` - replaced placeholder "Replay Delivery" link with actual replay button using POST method
  - Test: replay action resets delivery and enqueues job
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
- feat(final): add delivery detail view
  - Created `app/views/admin/webhook_deliveries/show.html.erb`
  - Features: shows delivery ID, status badge, endpoint info, event details, delivery status, timestamps, response excerpt, payload
  - Sections: status header, endpoint information, event information, delivery status info, timestamps, response body excerpt, payload (collapsible), actions (back, replay)
  - Test: show renders delivery details
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
- feat(final): add delivery filters and search
  - Updated `app/controllers/admin/webhook_deliveries_controller.rb` to apply filters by endpoint_id, event_type, status, event_id
  - Updated `app/views/admin/webhook_deliveries/index.html.erb` to add filter form with fields: endpoint dropdown, event_type text input, status dropdown, event_id text input
  - Test: index includes filter form
  - Test: index filters deliveries by endpoint
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
- feat(final): add deliveries index view
  - Created `app/views/admin/webhook_deliveries/index.html.erb`
  - Features: table with columns (ID, Endpoint, Event Type, Action, Status, HTTP Status, Created)
  - Links: ID links to delivery detail page
  - Styling: uses Redmine's standard table.list class
  - Test: index renders deliveries table with correct headers
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev
- feat(final): add webhook deliveries controller skeleton
  - Created `app/controllers/admin/webhook_deliveries_controller.rb`
  - Actions: index, show
  - Routes: added resources :webhook_deliveries under namespace :admin
  - Test: admin can access index
  - Cross-version tested: 5.1.0, 5.1.10, 6.1.0, 7.0.0-dev

### Changed
- (none)

### Fixed
- (none)
