# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:time_entries) do
      drop_column :original_message
    end
  end
  
  down do
    alter_table(:time_entries) do
      add_column :original_message, String, text: true
    end
  end
end
