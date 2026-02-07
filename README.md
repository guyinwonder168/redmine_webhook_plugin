# Redmine Webhook Plugin

Outbound webhook configuration for Redmine issues and time entries.

**Status:** Active Development. Admin UI, data model, event capture hooks, and robust delivery pipeline are fully implemented.

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Installation](#installation)
- [Usage](#usage)
- [Development](#development)
- [Testing](#testing)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Features

- **Endpoint Management**:
  - Admin UI to create, update, toggle, and delete webhook endpoints.
  - Project allowlist support for endpoint filtering.
  - Granular event selection for issues and time entries (created/updated/deleted).
  - Configurable SSL verification and request timeout per endpoint.
  - Payload mode selection (minimal/full) stored per endpoint.
  - Custom retry policy configuration (max attempts, base delay, max delay) per endpoint.
  - "Test" action to safely verify endpoint reachability.

- **Delivery System**:
  - robust delivery engine with selectable Execution Modes:
    - **Auto**: Automatically selects the best available method.
    - **ActiveJob**: Uses Redmine's ActiveJob (preserves background workers).
    - **DB Runner**: Database-backed queue runner.
  - Automatic retries with exponential backoff.
  - "Replay" capability for failed or successful deliveries (single and bulk).
  - CSV Export of delivery history (recent 1000 records).
  - Global "Pause" switch to stop all outgoing webhooks instantly.
  - Data retention policies for successful and failed deliveries.

- **Infrastructure**:
  - `HttpClient` with configurable timeout and redirect protection (max 5 redirects).
  - Secure API Key resolution for configured webhook users.
  - `X-Redmine-Signature` and standard headers support.

## Compatibility

- Redmine **>= 5.1.0**
- Tested against Redmine **5.1.0**, **5.1.10**, **6.1.0**, and **7.0.0-dev**
- Redmine 7.0+ includes native webhooks; this plugin disables native delivery to remain authoritative when installed.

## Installation

Install as a standard Redmine plugin:

1. Copy or symlink this repository into your Redmine instance:

```bash
# From your Redmine root
ln -s /path/to/redmine_webhook_plugin plugins/redmine_webhook_plugin
```

2. Run plugin migrations:

```bash
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
```

3. Restart Redmine.

## Configuration

Go to **Administration → Plugins → Redmine Webhook Plugin → Configure**.

- **Execution Mode**: Choose how webhooks are processed (Auto, ActiveJob, or DB Runner).
- **Retention Policy**: Set how many days to keep delivery records for Successful (default 7) and Failed (default 7) deliveries.
- **Pause Deliveries**: Globally suspend all webhook traffic without deleting configurations.

## Usage

### Managing Endpoints
1. Go to **Administration → Webhook Endpoints**.
2. Click **New Webhook Endpoint**.
3. Configure the endpoint:
   - **Name**: Descriptive name.
   - **URL**: Target HTTP/HTTPS URL.
   - **Authentication**: Assign a Redmine User context (api key from this user will be sent in headers).
   - **Timeout**: Request timeout in seconds (default 30).
   - **SSL Verify**: Disable only if testing against self-signed certs (default: Checked).
   - **Project Filter**: Select specific projects or leave empty for all.
   - **Events**: Check the issue/time_entry events to trigger this webhook.
   - **Retry Policy**: Adjust retry attempts and backoff timing.
4. Use the **Test** button on the list view to send a sample payload is reachable.

### Monitoring Deliveries
1. Go to **Administration → Webhook Deliveries**.
2. View the status of recent deliveries (Pending, Delivered, Failed).
3. Filter by Endpoint, Event Type, or Status.
4. **Replay**: Click the "Replay" button on any delivery to queue it for re-execution.
5. **Bulk Replay**: Select multiple failed deliveries and click "Replay Selected".
6. **Export**: Use the CSV export link to analyze delivery performance (limited to recent 1000 records).

## Development

This repo is self-contained for multi-version testing:

- Redmine sources live in `.redmine-test/redmine-<version>`.
- Bundler cache lives in `.bundle-cache/<version>`.
- Scripts are under `tools/`.

Start a local Redmine instance (Podman):

```bash
tools/dev/start-redmine.sh 5.1.0
tools/dev/start-redmine.sh 7.0.0-dev
```

## Testing

Use the unified test runner (recommended):

```bash
VERSION=5.1.0 tools/test/run-test.sh
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
VERSION=7.0.0-dev tools/test/run-test.sh
```

Run integration tests only:

```bash
VERSION=5.1.0 tools/test/run-integration-test.sh
VERSION=5.1.10 tools/test/run-integration-test.sh
VERSION=6.1.0 tools/test/run-integration-test.sh
VERSION=7.0.0-dev tools/test/run-integration-test.sh
```

## Documentation

- Docs index: [docs/README.md](docs/README.md)
- Development guide: [docs/development.md](docs/development.md)
- Testing guide: [docs/testing-guide.md](docs/testing-guide.md)
- PRD (v1.0.0): [docs/redmine-webhook-plugin-prd-v100.md](docs/redmine-webhook-plugin-prd-v100.md)
- Design (v1): [docs/design/v1-redmine-webhook-plugin-design.md](docs/design/v1-redmine-webhook-plugin-design.md)
- Development plan (v1): [docs/plans/v1-redmine-webhook-plugin-development-plan.md](docs/plans/v1-redmine-webhook-plugin-development-plan.md)
- Admin UI wireframes (v1): [docs/UIUX/v1-redmine-webhook-plugin-wireframes.md](docs/UIUX/v1-redmine-webhook-plugin-wireframes.md)
- Wiki: [GitHub Wiki](https://github.com/guyinwonder168/redmine_webhook_plugin/wiki)

## Contributing

See `CONTRIBUTING.md` for contribution guidelines and development workflow.

## Security

See `SECURITY.md`.

## License

See `LICENSE`.
