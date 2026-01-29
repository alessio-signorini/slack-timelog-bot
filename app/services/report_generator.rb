# frozen_string_literal: true

require 'csv'

module TimelogBot
  module Services
    class ReportGenerator
      class << self
        # Generate a user's personal report: projects as rows, months as columns
        def user_report(user_id:)
          entries = Models::TimeEntry.where(user_id: user_id).all
          return nil if entries.empty?

          # Get all months with entries
          months = entries.map { |e| e.date.strftime('%Y-%m') }.uniq.sort
          
          # Get all projects the user has logged time on
          project_ids = entries.map(&:project_id).uniq
          projects = Models::Project.where(id: project_ids).order(:name).all

          # Build data structure: { project_id => { month => total_minutes } }
          data = Hash.new { |h, k| h[k] = Hash.new(0) }
          entries.each do |entry|
            month = entry.date.strftime('%Y-%m')
            data[entry.project_id][month] += entry.minutes
          end

          # Generate CSV
          CSV.generate do |csv|
            # Header row: Project, Month1, Month2, ..., Total
            csv << ['Project'] + months.map { |m| format_month(m) } + ['Total']

            # Data rows
            projects.each do |project|
              row = [project.name]
              row_total = 0

              months.each do |month|
                minutes = data[project.id][month]
                row_total += minutes
                row << format_hours(minutes)
              end

              row << format_hours(row_total)
              csv << row
            end

            # Total row
            total_row = ['TOTAL']
            grand_total = 0

            months.each do |month|
              month_total = entries.select { |e| e.date.strftime('%Y-%m') == month }.sum(&:minutes)
              grand_total += month_total
              total_row << format_hours(month_total)
            end

            total_row << format_hours(grand_total)
            csv << total_row
          end
        end

        # Generate team report for a specific month: users as rows, projects as columns
        def team_report(month:)
          # Calculate date range for the month
          start_date = Date.new(month.year, month.month, 1)
          end_date = start_date.next_month - 1

          entries = Models::TimeEntry
            .where { date >= start_date }
            .where { date <= end_date }
            .all

          return nil if entries.empty?

          # Get all users and projects
          user_ids = entries.map(&:user_id).uniq
          project_ids = entries.map(&:project_id).uniq
          
          users = Models::User.where(id: user_ids).all.sort_by { |u| u.display_name.downcase }
          projects = Models::Project.where(id: project_ids).order(:name).all

          # Build data structure: { user_id => { project_id => total_minutes } }
          data = Hash.new { |h, k| h[k] = Hash.new(0) }
          entries.each do |entry|
            data[entry.user_id][entry.project_id] += entry.minutes
          end

          # Generate CSV
          CSV.generate do |csv|
            # Header row: User, Project1, Project2, ..., Total
            csv << ['User'] + projects.map(&:name) + ['Total']

            # Data rows
            users.each do |user|
              row = [user.display_name]
              row_total = 0

              projects.each do |project|
                minutes = data[user.id][project.id]
                row_total += minutes
                row << format_hours(minutes)
              end

              row << format_hours(row_total)
              csv << row
            end

            # Total row
            total_row = ['TOTAL']
            grand_total = 0

            projects.each do |project|
              project_total = entries.select { |e| e.project_id == project.id }.sum(&:minutes)
              grand_total += project_total
              total_row << format_hours(project_total)
            end

            total_row << format_hours(grand_total)
            csv << total_row
          end
        end

        private

        def format_hours(minutes)
          return '0' if minutes.nil? || minutes.zero?
          
          hours = minutes.to_f / 60
          # Round to 2 decimal places, remove trailing zeros
          formatted = format('%.2f', hours).sub(/\.?0+$/, '')
          formatted
        end

        def format_month(month_str)
          year, month = month_str.split('-')
          Date.new(year.to_i, month.to_i, 1).strftime('%b %Y')
        end
      end
    end
  end
end
