# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:event_logs) do
      add_column :original_message, String, text: true
    end
  end
end
