class CreateWebhookDeliveries < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:webhook_deliveries)

    create_table :webhook_deliveries do |t|
      t.integer :endpoint_id
      t.integer :webhook_user_id

      t.string :event_id, limit: 36, null: false
      t.string :event_type, null: false
      t.string :action, null: false
      t.string :resource_type
      t.integer :resource_id
      t.bigint :sequence_number

      t.text :payload, limit: 16.megabytes - 1
      t.text :endpoint_url
      t.text :retry_policy_snapshot

      t.string :status, default: "pending", null: false
      t.integer :attempt_count, default: 0, null: false
      t.integer :http_status
      t.string :error_code

      t.datetime :scheduled_at
      t.datetime :delivered_at
      t.integer :duration_ms

      t.datetime :locked_at
      t.string :locked_by

      t.text :response_body_excerpt
      t.string :api_key_fingerprint
      t.boolean :is_test, default: false

      t.timestamps null: false
    end

    add_index :webhook_deliveries, [:endpoint_id, :status]
    add_index :webhook_deliveries, [:resource_type, :resource_id]
    add_index :webhook_deliveries, :event_id
    add_index :webhook_deliveries, :scheduled_at
    add_index :webhook_deliveries, :status
  end
end