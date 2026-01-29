# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:time_entries) do
      add_foreign_key :event_log_id, :event_logs, null: true, on_delete: :set_null
      add_index :event_log_id
    end
  end
end
