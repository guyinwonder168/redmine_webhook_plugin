require File.expand_path("../test_helper", __dir__)

class WebhookEndpointMigrationTest < ActiveSupport::TestCase
  test "webhook_endpoints table exists with required columns" do
    assert ActiveRecord::Base.connection.table_exists?(:webhook_endpoints),
           "webhook_endpoints table should exist"

    columns = ActiveRecord::Base.connection.columns(:webhook_endpoints).map(&:name)

    assert_includes columns, "id"
    assert_includes columns, "name"
    assert_includes columns, "url"
    assert_includes columns, "enabled"
    assert_includes columns, "webhook_user_id"
    assert_includes columns, "payload_mode"
    assert_includes columns, "events_config"
    assert_includes columns, "project_ids"
    assert_includes columns, "retry_config"
    assert_includes columns, "timeout"
    assert_includes columns, "ssl_verify"
    assert_includes columns, "bulk_replay_rate_limit"
    assert_includes columns, "created_at"
    assert_includes columns, "updated_at"
  end
end