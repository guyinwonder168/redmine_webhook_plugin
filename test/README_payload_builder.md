# PayloadBuilder Usage Guide

## Overview

The `PayloadBuilder` service constructs webhook payloads for Redmine events. It supports two payload modes and includes comprehensive validation and size limiting.

## Initialization

```ruby
require_relative "app/services/webhook/payload_builder"

event_data = {
  event_type: "issue",
  action: "created",
  event_id: "550e8400-e29b-41d4-a716-446655440000",
  sequence_number: 1694169600000000,
  occurred_at: Time.now,
  resource: issue,
  project: project,
  actor: user,
  changes: { status_id: [1, 2] },
  custom_field_changes: {},
  saved_changes: {},
  journal: nil
}

builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
```

### Parameters

- `event_data` (Hash, required): Event metadata and resource data
  - `event_type`: "issue" or "time_entry"
  - `action`: "created", "updated", or "deleted"
  - `event_id`: UUID string (via `EventHelpers.generate_event_id`)
  - `sequence_number`: Microsecond timestamp (via `EventHelpers.generate_sequence_number`)
  - `occurred_at`: Timestamp of the event
  - `resource`: The ActiveRecord object (for created/updated) or Hash (for deleted)
  - `project`: Project ActiveRecord object
  - `actor`: User who triggered the event (via `EventHelpers.resolve_actor`)
  - `changes`: Hash of changes for created/updated events
  - `saved_changes`: Detailed attribute changes
  - `custom_field_changes`: Hash of custom field changes
  - `journal`: Journal object (for issue updated events)
- `payload_mode` (String, optional): "minimal" (default) or "full"

## Payload Modes

### Minimal Mode

Includes only essential fields for lightweight payloads:

```ruby
builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")
payload = builder.build
```

**Issue Minimal Payload:**
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "issue",
  "action": "created",
  "occurred_at": "2024-01-08T12:00:00.000Z",
  "sequence_number": 1694169600000000,
  "delivery_mode": "minimal",
  "schema_version": "1.0",
  "actor": {
    "id": 1,
    "login": "admin",
    "name": "Redmine Admin"
  },
  "project": {
    "id": 1,
    "identifier": "test-project",
    "name": "Test Project"
  },
  "issue": {
    "id": 123,
    "url": "https://redmine.example.com/issues/123",
    "api_url": "https://redmine.example.com/issues/123.json",
    "tracker": {
      "id": 1,
      "name": "Bug"
    }
  },
  "changes": [...]
}
```

**Time Entry Minimal Payload:**
```json
{
  "time_entry": {
    "id": 456,
    "url": "https://redmine.example.com/time_entries/456",
    "api_url": "https://redmine.example.com/time_entries/456.json",
    "issue": {
      "id": 123,
      "subject": "Issue subject"
    }
  }
}
```

### Full Mode

Includes complete resource data with all attributes:

```ruby
builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "full")
payload = builder.build
```

**Issue Full Payload:**
```json
{
  "issue": {
    "id": 123,
    "url": "https://redmine.example.com/issues/123",
    "api_url": "https://redmine.example.com/issues/123.json",
    "subject": "Issue subject",
    "description": "Issue description",
    "status": {
      "id": 2,
      "name": "In Progress"
    },
    "priority": {
      "id": 4,
      "name": "Normal"
    },
    "assigned_to": {
      "id": 2,
      "login": "developer",
      "name": "John Developer"
    },
    "author": {
      "id": 1,
      "login": "admin",
      "name": "Redmine Admin"
    },
    "start_date": "2024-01-01",
    "due_date": "2024-01-31",
    "created_on": "2024-01-08T12:00:00.000Z",
    "updated_on": "2024-01-08T12:30:00.000Z",
    "done_ratio": 50,
    "estimated_hours": 8.0,
    "parent_issue": {
      "id": 100,
      "subject": "Parent issue"
    },
    "custom_fields": [
      {
        "id": 1,
        "name": "Custom Field",
        "value": "Custom value"
      }
    ]
  }
}
```

## Change Tracking

The PayloadBuilder includes detailed change tracking for update events:

```ruby
changes = [
  {
    "field": "status_id",
    "kind": "attribute",
    "old": {
      "raw": 1,
      "text": "New"
    },
    "new": {
      "raw": 2,
      "text": "In Progress"
    }
  },
  {
    "field": "custom_field:5",
    "kind": "custom_field",
    "name": "Priority Level",
    "old": {
      "raw": "Low",
      "text": "Low"
    },
    "new": {
      "raw": "High",
      "text": "High"
    }
  }
]
```

## Delete Events

For delete events, a pre-delete snapshot is included:

```ruby
event_data = {
  event_type: "issue",
  action: "deleted",
  resource_snapshot: {
    id: 123,
    subject: "Deleted issue",
    project_id: 1,
    status_id: 2
  },
  resource: { type: "issue", id: 123, project_id: 1 },
  # ... other event data
}
```

**Delete Payload:**
```json
{
  "event_type": "issue",
  "action": "deleted",
  "resource": {
    "type": "issue",
    "id": 123,
    "project_id": 1
  },
  "resource_snapshot": {
    "snapshot_type": "pre_delete",
    "id": 123,
    "subject": "Deleted issue",
    "status": { "id": 2, "name": "In Progress" },
    "tracker": { "id": 1, "name": "Bug" },
    "priority": { "id": 4, "name": "Normal" },
    "author": { "id": 1, "login": "admin", "name": "Redmine Admin" },
    "project": { "id": 1, "identifier": "test-project", "name": "Test Project" }
  },
  "changes": {...}
}
```

## Size Limiting

The PayloadBuilder enforces a 1MB maximum payload size with progressive optimization:

1. **Truncate changes** (keeps last 100 changes if more)
2. **Exclude custom fields** (removes all custom field data)
3. **Raise error** if still too large

```ruby
begin
  payload = builder.build
rescue RedmineWebhookPlugin::Webhook::PayloadBuilder::PayloadTooLargeError => e
  puts e.message
end
```

## Event ID Generation

Generate unique event IDs:

```ruby
include RedmineWebhookPlugin::EventHelpers

event_id = generate_event_id
# => "550e8400-e29b-41d4-a716-446655440000"
```

## Sequence Number Generation

Generate microsecond-precision sequence numbers:

```ruby
include RedmineWebhookPlugin::EventHelpers

sequence_number = generate_sequence_number
# => 1694169600000000
```

## Actor Resolution

Resolve the current user as event actor:

```ruby
include RedmineWebhookPlugin::EventHelpers

actor = resolve_actor
# => { id: 1, login: "admin", name: "Redmine Admin" }
# => nil (for anonymous users)
```

## URL Generation

The PayloadBuilder generates both web UI and REST API URLs:

```json
{
  "url": "https://redmine.example.com/issues/123",
  "api_url": "https://redmine.example.com/issues/123.json"
}
```

URLs are constructed from Redmine's `Setting.protocol` and `Setting.host_name` configuration.

## Validation

The PayloadBuilder validates input on initialization:

```ruby
builder = RedmineWebhookPlugin::Webhook::PayloadBuilder.new(event_data, "minimal")

# Raises ArgumentError if:
# - event_data is not a Hash
# - event_type is missing or invalid
# - action is missing or invalid
# - payload_mode is invalid
```

Valid values:
- `event_type`: "issue", "time_entry"
- `action`: "created", "updated", "deleted"
- `payload_mode`: "minimal", "full"

## Example: Complete Workflow

```ruby
module RedmineWebhookPlugin
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern
      include EventHelpers

      def webhook_after_create
        return if @webhook_skip

        event_data = {
          event_type: "issue",
          action: "created",
          event_id: generate_event_id,
          sequence_number: generate_sequence_number,
          occurred_at: Time.now,
          resource: self,
          project: project,
          actor: resolve_actor,
          changes: @webhook_changes
        }

        builder = PayloadBuilder.new(event_data, "minimal")
        payload = builder.build

        Dispatcher.dispatch(payload)
      end
    end
  end
end
```

## Error Handling

The PayloadBuilder gracefully handles missing associations and nil values:

```ruby
serialize_actor(nil)
# => nil

serialize_project(nil)
# => nil

serialize_time_entry_issue_minimal(nil)
# => nil
```

Custom fields are only included if the resource responds to `custom_field_values`.

## Performance Considerations

- `base_url` is cached after first computation
- Payload size is only calculated when enforcing limits
- Associations are lazy-loaded only when needed (full mode)
- Change tracking uses `changes_to_save` to avoid re-querying the database

## Schema Version

The current schema version is `"1.0"`. This allows for future breaking changes while maintaining backward compatibility.

## Testing

See `test/unit/payload_builder_test.rb` for comprehensive test coverage (42 tests).
