# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:time_entries) do
      add_column :original_message, String, text: true
    end
  end
end
