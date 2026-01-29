# frozen_string_literal: true

module TimelogBot
  module Models
    class TimeEntry < Sequel::Model(DB[:time_entries])
      many_to_one :user
      many_to_one :project

      def hours
        (minutes.to_f / 60).round(2)
      end

      def hours=(value)
        self.minutes = (value.to_f * 60).round
      end

      # Get all entries for a user, optionally filtered by date range
      def self.for_user(user_id, start_date: nil, end_date: nil)
        dataset = where(user_id: user_id)
        dataset = dataset.where { date >= start_date } if start_date
        dataset = dataset.where { date <= end_date } if end_date
        dataset.order(:date)
      end

      # Get all entries for a project, optionally filtered by date range
      def self.for_project(project_id, start_date: nil, end_date: nil)
        dataset = where(project_id: project_id)
        dataset = dataset.where { date >= start_date } if start_date
        dataset = dataset.where { date <= end_date } if end_date
        dataset.order(:date)
      end

      # Aggregate hours by project for a user
      def self.hours_by_project_for_user(user_id)
        where(user_id: user_id)
          .select_group(:project_id)
          .select_append { sum(minutes).as(total_minutes) }
          .all
          .map { |row| { project_id: row[:project_id], hours: (row[:total_minutes].to_f / 60).round(2) } }
      end

      # Aggregate hours by user for a project
      def self.hours_by_user_for_project(project_id)
        where(project_id: project_id)
          .select_group(:user_id)
          .select_append { sum(minutes).as(total_minutes) }
          .all
          .map { |row| { user_id: row[:user_id], hours: (row[:total_minutes].to_f / 60).round(2) } }
      end

      # Get entries grouped by month (for reporting)
      def self.by_month(user_id:, project_id: nil)
        dataset = where(user_id: user_id)
        dataset = dataset.where(project_id: project_id) if project_id
        
        dataset
          .select_group(Sequel.function(:strftime, '%Y-%m', :date).as(:month))
          .select_append { sum(minutes).as(total_minutes) }
          .order(:month)
          .all
      end
    end
  end
end
