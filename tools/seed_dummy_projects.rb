# Redmine Database Seeder - Dummy Projects

This script adds dummy project data to Redmine for testing the Webhook Endpoints configuration.

---

## Overview

The Webhook Endpoints form has a "Projects" multi-select field. This script populates the Redmine database with sample projects so you can test project-specific webhook filtering.

---

## Run Seeder

### Method 1: Using Rails Runner (Quick)

```bash
cd /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0

podman exec redmine-5-1-0 bash -lc '
  cd /redmine
  bundle exec rails runner "
    # Create dummy projects
    5.times do |i|
      Project.create!(
        name: \"Test Project #{i + 1}\",
        identifier: \"test-project-#{i + 1}\",
        description: \"A test project for webhook endpoint testing\",
        is_public: true,
        status: Project::STATUS_ACTIVE
      )
      puts \"Created: Test Project #{i + 1}\"
    end
    puts \"✓ Dummy projects seeded successfully!\"
  "
'
```

### Method 2: Using Seed File (Reusable)

#### Step 1: Create Seed File

```bash
cat > /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/seeds.rb <<'EOF'
# db/seeds.rb - Dummy project seeder for webhook testing

puts "Seeding dummy projects for webhook testing..."

# Create dummy projects
5.times do |i|
  Project.create!(
    name: "Test Project #{i + 1}",
    identifier: "test-project-#{i + 1}",
    description: "A test project for webhook endpoint testing",
    is_public: true,
    status: Project::STATUS_ACTIVE
  )
  puts "Created: Test Project #{i + 1}"
end

puts "✓ Dummy projects seeded successfully!"
EOF
```

#### Step 2: Run Seed

```bash
podman exec redmine-5-1-0 bash -lc '
  cd /redmine
  bundle exec rake db:seed RAILS_ENV=development
'
```

---

## Verify Projects Were Created

### In Rails Console

```bash
podman exec redmine-5-1-0 bash -lc '
  cd /redmine
  bundle exec rails runner "puts Project.count"
'
# Should output a number >= 5
```

### In Browser

1. Log in to Redmine (http://localhost:3000)
2. Navigate to **Projects**
3. You should see:
   - Test Project 1
   - Test Project 2
   - Test Project 3
   - Test Project 4
   - Test Project 5

### In Webhook Endpoints Form

1. Go to **Administration → Webhook Endpoints**
2. Click **"New Endpoint"**
3. Scroll to **Projects** field
4. Click the multi-select dropdown
5. You should see the dummy projects available for selection

---

## Customizing Project Data

### Create Different Number of Projects

Change `5.times` to any number you want:

```ruby
10.times do |i|
  Project.create!(
    name: "Project #{i + 1}",
    identifier: "project-#{i + 1}",
    description: "Test project #{i + 1}",
    is_public: true,
    status: Project::STATUS_ACTIVE
  )
end
```

### Add More Realistic Data

```ruby
projects = [
  { name: "Marketing Website", identifier: "marketing-web", description: "Company marketing website" },
  { name: "Mobile App", identifier: "mobile-app", description: "iOS and Android mobile application" },
  { name: "API Services", identifier: "api-services", description: "REST API endpoints" },
  { name: "Internal Tools", identifier: "internal-tools", description: "Developer tools and dashboards" },
  { name: "Documentation", identifier: "docs", description: "Project documentation and wikis" }
]

projects.each do |proj|
  Project.create!(
    name: proj[:name],
    identifier: proj[:identifier],
    description: proj[:description],
    is_public: true,
    status: Project::STATUS_ACTIVE
  )
  puts "Created: #{proj[:name]}"
end
```

---

## Resetting Database

If you want to start fresh:

```bash
# Stop Redmine
podman stop redmine-5-1-0
podman rm redmine-5-1-0

# Remove database
rm /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0/db/redmine.sqlite3

# Restart Redmine (will create fresh database)
podman run -d --name redmine-5-1-0 \
  -p 3000:3000 \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.redmine-test/redmine-5.1.0:/redmine:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin:/redmine/plugins/redmine_webhook_plugin:rw \
  -v /media/eddy/hdd/Project/redmine_webhook_plugin/.bundle-cache/5.1.0:/bundle:rw \
  -e BUNDLE_PATH=/bundle \
  redmine-dev:5.1.0 \
  bash -lc 'cd /redmine && bundle exec rails server -b 0.0.0.0 -p 3000 -e development'
```

---

## Summary

| What | How |
|-------|------|
| Add 5 dummy projects | Use rails runner or db:seed |
| Verify projects created | Check Projects page in browser |
| Test with webhooks | Select projects in webhook form |
| Reset database | Remove .sqlite3 and restart |

---

**Last Updated:** 2025-12-30
**Purpose:** Test webhook project filtering feature
