class CreateWebhookEndpoints < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:webhook_endpoints)

    create_table :webhook_endpoints do |t|
      t.string :name, null: false
      t.text :url, null: false
      t.boolean :enabled, default: true, null: false
      t.integer :webhook_user_id

      t.string :payload_mode, default: "minimal", null: false
      t.text :events_config
      t.text :project_ids
      t.text :retry_config

      t.integer :timeout, default: 30
      t.boolean :ssl_verify, default: true
      t.integer :bulk_replay_rate_limit, default: 10

      t.timestamps null: false
    end

    add_index :webhook_endpoints, :webhook_user_id
    add_index :webhook_endpoints, :enabled
  end
end