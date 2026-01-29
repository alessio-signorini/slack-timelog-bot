# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:users) do
      add_column :is_bot, TrueClass, default: false, null: false
      add_index :is_bot
    end
  end
end
