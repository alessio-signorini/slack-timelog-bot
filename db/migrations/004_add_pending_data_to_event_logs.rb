# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:event_logs) do
      add_column :message_ts, String    # Slack message timestamp for correlation
      add_column :channel_id, String    # Channel where message was sent
      add_column :user_id, String       # User who triggered the event
      add_column :pending_data, String, text: true  # JSON data for pending operations
      
      add_index :message_ts
    end
  end
end
