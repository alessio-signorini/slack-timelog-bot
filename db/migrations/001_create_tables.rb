# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id
      String :slack_user_id, null: false, unique: true
      String :slack_username
      String :timezone, default: 'America/Los_Angeles'
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slack_user_id
    end

    create_table(:projects) do
      primary_key :id
      String :name, null: false, unique: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :name
    end

    create_table(:time_entries) do
      primary_key :id
      foreign_key :user_id, :users, null: false, on_delete: :cascade
      foreign_key :project_id, :projects, null: false, on_delete: :cascade
      Integer :minutes, null: false
      Date :date, null: false
      String :notes, text: true
      String :logged_by_slack_id, null: false  # Who logged this entry
      DateTime :logged_at, default: Sequel::CURRENT_TIMESTAMP

      index :user_id
      index :project_id
      index :date
      index [:user_id, :date]
      index [:project_id, :date]
    end
  end
end
