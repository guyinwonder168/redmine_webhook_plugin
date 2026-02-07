# Development Guide

This guide covers local development setup for the Redmine Webhook Plugin.

## Environment Setup

### Ruby/Rails Versions

The plugin supports multiple Redmine versions:

- **Redmine 5.1.0**: Ruby 3.1+, Rails 7.0
- **Redmine 5.1.10**: Ruby 3.2+, Rails 7.0
- **Redmine 6.1.0**: Ruby 3.2+, Rails 7.2
- **Redmine 7.0.0-dev**: Ruby 3.3+, Rails 8.0.4

**Redmine 7.0+ Compatibility:** Redmine 7.0+ introduces native webhooks. When native webhooks are present, the plugin remains authoritative and disables or bypasses native delivery to avoid duplicates.

**Recommended Development Environment:**
- Ruby 3.2.2 (via rbenv or rvm)
- Node.js 18+ (for asset compilation)
- PostgreSQL 13+ or MySQL 8.0+ (for development)

### Database Requirements

**For Development:**
- SQLite (default, no setup required)
- PostgreSQL (recommended for production-like testing)
- MySQL (legacy support)

**Database Setup (PostgreSQL):**
```bash
# Install PostgreSQL
sudo apt-get install postgresql postgresql-contrib

# Create development database
sudo -u postgres createdb redmine_dev
sudo -u postgres createuser --createdb redmine_user
sudo -u postgres psql -c "ALTER USER redmine_user PASSWORD 'redmine_pass';"
```

### Development Tools

**Required:**
- Git
- Ruby (with bundler)
- Node.js/npm (for stylelint)

**Recommended:**
- Docker/Podman (for containerized development)
- VS Code (with Ruby extensions)
- Chrome (for system tests)

## Plugin Installation

### Method 1: Symlink Method (Current/Recommended)

```bash
# Clone Redmine
git clone https://github.com/redmine/redmine.git .redmine-test/redmine-5.1.0
cd .redmine-test/redmine-5.1.0

# Setup Redmine
bundle install
cp config/database.yml.example config/database.yml
cp config/configuration.yml.example config/configuration.yml
bundle exec rake generate_secret_token
bundle exec rake db:migrate

# Symlink plugin
ln -s /media/eddy/hdd/Project/redmine_webhook_plugin plugins/redmine_webhook_plugin

# Install plugin dependencies
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
```

### Method 2: Copy Method

```bash
# Copy plugin to plugins directory
cp -r /media/eddy/hdd/Project/redmine_webhook_plugin .redmine-test/redmine-5.1.0/plugins/

# Install dependencies
cd .redmine-test/redmine-5.1.0
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
```

### Method 3: Git Submodule Method

```bash
# Add as submodule
cd .redmine-test/redmine-5.1.0
git submodule add https://github.com/your-org/redmine_webhook_plugin plugins/redmine_webhook_plugin

# Install dependencies
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
```

## Running Development Server

### Using Plugin Scripts

```bash
# From plugin directory
cd /media/eddy/hdd/Project/redmine_webhook_plugin

# Start server (auto-detects Redmine location)
tools/dev/start-redmine.sh 5.1.0

# Or start the 7.0.0-dev container
tools/dev/start-redmine.sh 7.0.0-dev

# Server will be available at http://localhost:3000 (5.1.0) or http://localhost:3003 (7.0.0-dev)
```

### Manual Server Start

```bash
# From Redmine directory
cd .redmine-test/redmine-5.1.0

# Start server
bundle exec rails server

# Or with specific options
bundle exec rails server -p 3000 -b 0.0.0.0
```

### Container-Based Development

```bash
# Using Podman/Docker
cd /media/eddy/hdd/Project/redmine_webhook_plugin

# Build and run
podman build -f tools/docker/Containerfile.redmine -t redmine-dev .
podman run -p 3000:3000 -v $(pwd):/app/plugins/redmine_webhook_plugin redmine-dev
```

## Database Management

### Migrations

**Plugin Migrations:**
```bash
# From Redmine directory
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin

# Rollback specific migration
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin VERSION=0
```

**Core Migrations:**
```bash
# Standard Rails migrations
bundle exec rake db:migrate
bundle exec rake db:rollback
```

### Seeds

**Plugin Seeds:**
```bash
# Load plugin seed data
bundle exec rake redmine:plugins:seed NAME=redmine_webhook_plugin
```

**Custom Seed Script:**
The plugin includes `create_admin_and_projects.rb` for setting up test data:

```bash
# From plugin directory
ruby create_admin_and_projects.rb
```

### Test Data

**Creating Test Webhooks:**
```ruby
# In Rails console
WebhookEndpoint.create!(
  name: 'Test Endpoint',
  url: 'http://localhost:8080/webhook',
  enabled: true,
  events: ['issue_created', 'issue_updated'],
  user: User.first,
  project: Project.first
)
```

## Testing Workflow

### Running Tests Locally

**Using Plugin Scripts:**
```bash
cd /media/eddy/hdd/Project/redmine_webhook_plugin

# Test specific version
tools/test/test-5.1.0.sh

# Test all versions
tools/test/test-5.1.0.sh && tools/test/test-5.1.10.sh && tools/test/test-6.1.0.sh && tools/test/test-7.0.0-dev.sh
```

**Manual Test Run:**
```bash
# From Redmine directory
bundle exec rake redmine:plugins:test NAME=redmine_webhook_plugin

# Run specific test file
ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_endpoint_test.rb

# Run specific test method
ruby -Ilib:test plugins/redmine_webhook_plugin/test/unit/webhook_endpoint_test.rb -n test_create
```

### Writing New Tests

**Unit Test Example:**
```ruby
# test/unit/webhook_endpoint_test.rb
require 'test_helper'

class WebhookEndpointTest < ActiveSupport::TestCase
  test 'should validate presence of name' do
    endpoint = WebhookEndpoint.new
    assert_not endpoint.valid?
    assert_includes endpoint.errors[:name], "can't be blank"
  end
end
```

**Functional Test Example:**
```ruby
# test/functional/admin/webhook_endpoints_controller_test.rb
require 'test_helper'

class Admin::WebhookEndpointsControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
  end
end
```

### Debugging Test Failures

**Enable Debug Logging:**
```bash
# In test environment
export RAILS_ENV=test
export DEBUG=true

# Run tests with verbose output
bundle exec rake redmine:plugins:test NAME=redmine_webhook_plugin --trace
```

**Common Issues:**
- Database not migrated: Run `bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin RAILS_ENV=test`
- Missing fixtures: Check `test/fixtures/` directory
- Permission issues: Ensure test database is writable

## Code Style & Linting

### RuboCop Configuration

The project uses RuboCop for Ruby code style enforcement:

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix safe issues
bundle exec rubocop -a

# Check specific file
bundle exec rubocop app/models/webhook_endpoint.rb
```

**Key Rules:**
- 2-space indentation
- Snake_case for methods/variables
- CamelCase for classes/modules
- `# frozen_string_literal: true` at file top (except migrations)
- Line length: 120 characters

### CSS Linting

```bash
# Run stylelint on CSS files
npx stylelint "app/assets/stylesheets/**/*.css"

# Auto-fix issues
npx stylelint "app/assets/stylesheets/**/*.css" --fix
```

### Pre-commit Hooks

**Recommended Setup:**
```bash
# Install pre-commit hook
cp .git/hooks/pre-commit.sample .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Add to pre-commit hook:
#!/bin/sh
bundle exec rubocop --parallel
npx stylelint "app/assets/stylesheets/**/*.css"
```

### CI Checks

**GitLab CI Configuration:**
```yaml
lint:
  script:
    - bundle exec rubocop --parallel
    - npx stylelint "app/assets/stylesheets/**/*.css"
    - bundle exec rake test:units
    - bundle exec rake test:functionals
```

## Troubleshooting

### Common Development Issues

**Plugin Not Loading:**
```bash
# Check plugin registration
bundle exec rails runner "puts Redmine::Plugin.all.keys"

# Verify plugin directory structure
ls -la plugins/redmine_webhook_plugin/
```

**Migration Errors:**
```bash
# Reset plugin migrations
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin VERSION=0
bundle exec rake redmine:plugins:migrate NAME=redmine_webhook_plugin
```

**Asset Compilation Issues:**
```bash
# Clear asset cache
bundle exec rake assets:clean
bundle exec rake assets:precompile
```

### Performance Tips

**Development Mode Optimizations:**
```ruby
# config/environments/development.rb
config.cache_classes = false
config.eager_load = false
config.assets.debug = true
```

**Database Query Optimization:**
```ruby
# Use includes for eager loading
@webhooks = WebhookEndpoint.includes(:user, :project).all
```

## Contributing

### Development Workflow

1. Create feature branch: `git checkout -b feature/new-webhook-events`
2. Make changes with tests
3. Run full test suite: `tools/test/run-test.sh VERSION=all` or test individually: `VERSION=5.1.0 tools/test/run-test.sh && VERSION=5.1.10 tools/test/run-test.sh && VERSION=6.1.0 tools/test/run-test.sh && VERSION=7.0.0-dev tools/test/run-test.sh`
4. Update documentation if needed
5. Commit with conventional format: `git commit -m "feat: Add support for project events"`
6. Create pull request

### Code Review Checklist

- [ ] Tests pass on all supported Redmine versions (5.1.0, 5.1.10, 6.1.0, 7.0.0-dev)
- [ ] Code follows style guidelines (RuboCop)
- [ ] Documentation updated
- [ ] Migration files include rollback
- [ ] No security vulnerabilities
- [ ] Performance impact assessed

## See Also

- [Testing Guide](testing.md) - Comprehensive testing documentation
- [Plugin README](../README.md) - Plugin overview and features
- [API Documentation](api.md) - Webhook payload specifications
