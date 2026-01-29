# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:event_logs) do
      primary_key :id
      String :event_id, null: false, unique: true
      String :event_type
      DateTime :processed_at, default: Sequel::CURRENT_TIMESTAMP

      index :event_id, unique: true
      index :processed_at
    end
  end
end
