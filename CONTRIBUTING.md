# Contributing

This repository is intended for public collaboration.

[[_TOC_]]

## Documentation

- Docs index: [docs/README.md](docs/README.md)
- Development guide: [docs/development.md](docs/development.md)
- Testing guide: [docs/testing-guide.md](docs/testing-guide.md)

## Workflow

- Create a feature branch from `main` (or the current integration branch if agreed):
  - `feat/...`, `fix/...`, `chore/...`
- Open a pull request and request review.
- Prefer small, focused MRs.

## Development workflow (summary)

Keep this file short and defer to `docs/development.md` for details. The current repo layout is self-contained under this plugin root:

- Redmine sources: `.redmine-test/redmine-<version>`
- Bundler cache: `.bundle-cache/<version>`
- Scripts: `tools/`

Quick start (from `/media/eddy/hdd/Project/redmine_webhook_plugin`):

```bash
# Download Redmine and run tests
VERSION=5.1.0 tools/test/run-test.sh
VERSION=5.1.10 tools/test/run-test.sh
VERSION=6.1.0 tools/test/run-test.sh
VERSION=7.0.0-dev tools/test/run-test.sh

# Optional 7.0.0-dev smoke run
tools/test/test-7.0.0-dev.sh

# Optional: start Redmine for manual testing
tools/dev/start-redmine.sh 5.1.0
# tools/dev/start-redmine.sh 7.0.0-dev
```

## Quality checklist

- Keep changes compatible with **Redmine >= 5.1.0** (tested through **6.1.0**, plus 7.0.0-dev smoke runs)
- Add/update documentation in `docs/` when behavior changes
- Avoid committing secrets (API keys, tokens, passwords)
- Include tests where practical (especially payload/diff generation and delivery retry logic)

## CI compatibility matrix

GitHub Actions is the public CI entrypoint for repository checks.

- CI config: `.github/workflows/ci.yml`
- Release automation: `.github/workflows/release.yml`
- Local compatibility runner: `tools/ci/run_redmine_compat.sh`
