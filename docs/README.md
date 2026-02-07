# Redmine Dev/Test Environment (Self-Contained)

[[_TOC_]]

## Core docs (v1)

- PRD (v1.0.0): [redmine-webhook-plugin-prd-v100.md](redmine-webhook-plugin-prd-v100.md)
- Design (v1): [design/v1-redmine-webhook-plugin-design.md](design/v1-redmine-webhook-plugin-design.md)
- Development plan (v1): [plans/v1-redmine-webhook-plugin-development-plan.md](plans/v1-redmine-webhook-plugin-development-plan.md)
- Admin UI wireframes (v1): [UIUX/v1-redmine-webhook-plugin-wireframes.md](UIUX/v1-redmine-webhook-plugin-wireframes.md)

## Structure

- `design/`: design docs
- `plans/`: development/implementation plans
- `UIUX/`: UI/UX docs (wireframes)

## Overview

Self-contained workflow for running Redmine plugin tests against multiple Redmine versions. The repo manages Redmine sources under `.redmine-test/` and gem caches under `.bundle-cache/`. Podman remains optional for containerized runs.

**For comprehensive testing guidance** (including manual UI testing and browser testing), see [Testing Guide](testing-guide.md).

**Redmine 7.0+ note:** Native webhooks exist in trunk; when present, the plugin remains authoritative and disables or bypasses native delivery to avoid duplicates.

## Directory layout

Expected layout (adjust if yours differs):

- `/media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0` (Redmine 5.1-stable source)
- `/media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.10` (Redmine 5.1.10 source)
- `/media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-6.1.0` (Redmine 6.1.0 source)
- `/media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache` (Bundler cache)
- `/media/eddy/hdd/Project/redmine_webhook_plugin/tools` (scripts)

## Version matrix (from Gemfile)
- Redmine 5.1.x: Ruby >= 2.7.0 and < 3.3.0, Rails 6.1.7.10
- Redmine 6.1.0: Ruby >= 3.2.0 and < 3.5.0, Rails 8.0.4
- Redmine 7.0.0-dev: Ruby >= 3.3.0, Rails 8.0.4

Pick Ruby versions that satisfy those ranges (examples below use 3.2.2 for 5.1.x, 3.3.4 for 6.1.0, and 3.3.4 for 7.0.0-dev).

## Containerfile (optional Podman)

`tools/docker/Containerfile.redmine` is provided in this repo:

```Dockerfile
ARG RUBY_VERSION=3.2.2
FROM docker.io/library/ruby:${RUBY_VERSION}-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential git curl ca-certificates \
  libsqlite3-dev sqlite3 \
  libxml2-dev libxslt1-dev \
  libffi-dev libyaml-dev libreadline-dev zlib1g-dev libssl-dev pkg-config \
  nodejs \
  && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/bundle
WORKDIR /redmine
```

## Build images (local)

From `/media/eddy/hdd/Project/redmine_webhook_plugin`:

```bash
podman build -f tools/docker/Containerfile.redmine -t redmine-dev:5.1.0 --build-arg RUBY_VERSION=3.2.2 .
podman build -f tools/docker/Containerfile.redmine -t redmine-dev:5.1.10 --build-arg RUBY_VERSION=3.2.2 .
podman build -f tools/docker/Containerfile.redmine -t redmine-dev:6.1.0 --build-arg RUBY_VERSION=3.3.4 .
```

## Prepare runtime directories (one-time per version)

Create a bundle cache directory:

```bash
mkdir -p /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0
```

Repeat the same pattern for `5.1.10` and `6.1.0`.

## Run tests (workflow for every code change)

Each time you change plugin code, re-run the appropriate command. The Redmine source is mounted read-write (Bundler writes `Gemfile.lock`, and tests write `tmp/` and `log/`), while the plugin is mounted read-write. SQLite is the default test database.

Quick commands (self-contained runner):

```bash
VERSION=5.1.0 tools/test/run-test.sh
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
VERSION=7.0.0-dev tools/test/run-test.sh
```

Example for Redmine 5.1.0 (Podman):

```bash
podman run --rm -it \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'set -euo pipefail; cd /redmine; \
    printf "test:\n  adapter: sqlite3\n  database: db/redmine_test.sqlite3\n  pool: 5\n  timeout: 5000\n" > config/database.yml; \
    if ! bundle check; then bundle install --jobs 4 --retry 3; fi; \
    bundle exec rake db:drop db:create db:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test; \
    bundle exec rake redmine:plugins:test NAME=redmine_webhook_plugin RAILS_ENV=test'
```

Repeat with the other versions by changing the Redmine directory and image tag to `5.1.10`, `6.1.0`, or `7.0.0-dev`.

Note: If `.redmine-test/redmine-<version>` does not exist yet, run `VERSION=<version> tools/test/run-test.sh` once to download Redmine sources.

## SQLite default, other databases later

This workflow defaults to SQLite so the container is self-contained. To switch to MySQL/Postgres later, replace `config/database.yml` with your DB config (bind-mount it into `/redmine/config/database.yml`), and make sure the container can reach that DB. We are intentionally using Podman’s default network so later on it can communicate with host services.

If plugin tests cannot find `test_helper`, the run scripts set `RUBYLIB=/redmine/plugins/redmine_webhook_plugin/test` and run the test task via `ruby -I... -S rake` so `require "test_helper"` resolves without changing code.

## Notes

- If you are on SELinux-enforcing hosts, you may need to add `:Z` or `:z` to volume mounts.
- To speed up repeated runs, keep the bundle cache directories under `/media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/`.
- Redmine 5.1.10 may pull `minitest` 6; `.redmine-test/redmine-5.1.10/Gemfile.local` pins it to `~> 5.0` to avoid Rails 6.1 line-filtering errors.
- Redmine 6.1.0 uses `db:schema:load` instead of `db:migrate`/`db:prepare` because Rails 8 tries to run all legacy migrations sequentially, which fail with deprecated ActiveRecord patterns.
