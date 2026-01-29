# frozen_string_literal: true

module TimelogBot
  module Handlers
    class SlashCommandHandler
      REPORT_COMMANDS = %w[/report /team_report].freeze

      class << self
        def handle(params)
          command = params['command']
          text = params['text']&.strip || ''
          user_id = params['user_id']
          channel_id = params['channel_id']
          response_url = params['response_url']

          $logger.info("Slash command from #{user_id}: #{command} #{text}")

          case command
          when '/report'
            handle_report(user_id: user_id, channel_id: channel_id)
          when '/team_report'
            handle_team_report(user_id: user_id, channel_id: channel_id, text: text)
          when '/log'
            # If no response_url (e.g., in tests), process synchronously
            if response_url
              handle_log_async(user_id: user_id, channel_id: channel_id, text: text, response_url: response_url)
            else
              handle_log(user_id: user_id, channel_id: channel_id, text: text)
            end
          when '/team_log'
            # If no response_url (e.g., in tests), process synchronously
            if response_url
              handle_team_log_async(user_id: user_id, channel_id: channel_id, text: text, response_url: response_url)
            else
              handle_team_log(user_id: user_id, channel_id: channel_id, text: text)
            end
          when '/delete'
            handle_delete(user_id: user_id, channel_id: channel_id, text: text)
          else
            { text: "Unknown command: #{command}" }.to_json
          end
        rescue StandardError => e
          $logger.error("Error handling slash command: #{e.message}")
          $logger.error(e.backtrace.first(5).join("\n"))
          { text: "Sorry, something went wrong. Please try again." }.to_json
        end

        private

        def handle_report(user_id:, channel_id:)
          user = Services::UserService.find_or_create(user_id)
          
          csv_content = Services::ReportGenerator.user_report(user_id: user.id)

          if csv_content.nil? || csv_content.empty?
            return {
              response_type: 'ephemeral',
              text: "You don't have any time entries yet."
            }.to_json
          end

          # Upload CSV file
          filename = "time_report_#{user.slack_username || user_id}_#{Date.today.iso8601}.csv"
          
          Services::SlackClient.upload_file(
            channel: channel_id,
            content: csv_content,
            filename: filename,
            title: "Time Report for #{user.slack_username || user_id}",
            initial_comment: "Here's your time report!"
          )

          # Return empty response since file upload handles the message
          ''
        end

        def handle_team_report(user_id:, channel_id:, text:)
          # Check if user is authorized
          unless authorized_for_team_report?(user_id)
            return {
              response_type: 'ephemeral',
              text: "Sorry, you don't have permission to run team reports. Contact an admin if you need access."
            }.to_json
          end

          # Parse month argument (YYYY-MM format)
          month = parse_month_argument(text)
          
          csv_content = Services::ReportGenerator.team_report(month: month)

          if csv_content.nil? || csv_content.empty?
            return {
              response_type: 'ephemeral',
              text: "No time entries found for #{month.strftime('%B %Y')}."
            }.to_json
          end

          # Upload CSV file
          filename = "team_report_#{month.strftime('%Y-%m')}.csv"
          
          Services::SlackClient.upload_file(
            channel: channel_id,
            content: csv_content,
            filename: filename,
            title: "Team Report for #{month.strftime('%B %Y')}",
            initial_comment: "Here's the team report for #{month.strftime('%B %Y')}!"
          )

          # Return empty response since file upload handles the message
          ''
        end

        def handle_log_async(user_id:, channel_id:, text:, response_url:)
          # Immediately respond to avoid timeout
          Thread.new do
            begin
              result = handle_log(user_id: user_id, channel_id: channel_id, text: text)
              # Send result via response_url
              Services::SlackClient.post_to_response_url(response_url, Oj.load(result, symbol_keys: true))
            rescue StandardError => e
              $logger.error("Error in handle_log_async: #{e.message}")
              $logger.error(e.backtrace.first(5).join("\n"))
              Services::SlackClient.post_to_response_url(response_url, {
                response_type: 'ephemeral',
                text: "Sorry, something went wrong while fetching your logs. Please try again."
              })
            end
          end

          # Return immediate acknowledgment
          {
            response_type: 'ephemeral',
            text: '⏳ Processing your request...'
          }.to_json
        end

        def handle_log(user_id:, channel_id:, text:)
          user = Services::UserService.find_or_create(user_id)
          
          # Parse number of days from text, default to 60
          days = parse_days_argument(text)
          
          # Get last N days of entries for this user
          end_date = Date.today
          start_date = end_date - days
          
          entries = Models::TimeEntry
            .for_user(user.id, start_date: start_date, end_date: end_date)
            .eager(:project)
            .all

          if entries.empty?
            return {
              response_type: 'ephemeral',
              text: "You don't have any time entries in the last #{days} days."
            }.to_json
          end

          # Format entries as text
          lines = ["*Your Time Entries (Last #{days} Days)*\n"]
          
          entries.each do |entry|
            # Get who logged it
            logged_by = entry.logged_by_slack_id
            logged_by_name = if logged_by == user_id
              'you'
            else
              logged_user = DB[:users].where(slack_user_id: logged_by).first
              logged_user ? "@#{logged_user[:slack_username]}" : logged_by
            end
            
            # Format: ID | Date | User | Logged by | Project | Hours | Notes
            hours = entry.hours
            user_name = entry.user.slack_username || entry.user.slack_user_id
            project_name = entry.project.name
            notes = entry.notes || '—'
            
            lines << "• `#{entry.id}` | *#{entry.date}* | @#{user_name} | Logged by #{logged_by_name} | *#{project_name}* | #{hours}h | #{notes}"
          end
          
          # Calculate total
          total_hours = entries.sum(&:hours)
          lines << "\n*Total:* #{total_hours}h"

          {
            response_type: 'ephemeral',
            text: lines.join("\n")
          }.to_json
        end

        def handle_team_log_async(user_id:, channel_id:, text:, response_url:)
          # Immediately respond to avoid timeout
          Thread.new do
            begin
              result = handle_team_log(user_id: user_id, channel_id: channel_id, text: text)
              # Send result via response_url
              Services::SlackClient.post_to_response_url(response_url, Oj.load(result, symbol_keys: true))
            rescue StandardError => e
              $logger.error("Error in handle_team_log_async: #{e.message}")
              $logger.error(e.backtrace.first(5).join("\n"))
              Services::SlackClient.post_to_response_url(response_url, {
                response_type: 'ephemeral',
                text: "Sorry, something went wrong while fetching team logs. Please try again."
              })
            end
          end

          # Return immediate acknowledgment
          {
            response_type: 'ephemeral',
            text: '⏳ Processing your request...'
          }.to_json
        end

        def handle_team_log(user_id:, channel_id:, text:)
          # Check if user is authorized
          unless authorized_for_team_report?(user_id)
            return {
              response_type: 'ephemeral',
              text: "Sorry, you don't have permission to view team logs. Contact an admin if you need access."
            }.to_json
          end

          # Parse number of days from text, default to 60
          days = parse_days_argument(text)
          
          # Get last N days of entries for all users
          end_date = Date.today
          start_date = end_date - days
          
          entries = Models::TimeEntry
            .where { date >= start_date }
            .where { date <= end_date }
            .order(:date)
            .eager(:user, :project)
            .all

          if entries.empty?
            return {
              response_type: 'ephemeral',
              text: "No time entries found in the last #{days} days."
            }.to_json
          end

          # Format entries as text
          lines = ["*Team Time Entries (Last #{days} Days)*\n"]
          
          entries.each do |entry|
            # Get who logged it
            logged_by = entry.logged_by_slack_id
            logged_by_user = DB[:users].where(slack_user_id: logged_by).first
            logged_by_name = logged_by_user ? "@#{logged_by_user[:slack_username]}" : logged_by
            
            # Format: ID | Date | User | Logged by | Project | Hours | Notes
            hours = entry.hours
            user_name = entry.user.slack_username || entry.user.slack_user_id
            project_name = entry.project.name
            notes = entry.notes || '—'
            
            lines << "• `#{entry.id}` | *#{entry.date}* | @#{user_name} | Logged by #{logged_by_name} | *#{project_name}* | #{hours}h | #{notes}"
          end
          
          # Calculate total
          total_hours = entries.sum(&:hours)
          lines << "\n*Total:* #{total_hours}h"

          {
            response_type: 'ephemeral',
            text: lines.join("\n")
          }.to_json
        end

        def handle_delete(user_id:, channel_id:, text:)
          # Validate ID parameter is provided
          if text.nil? || text.strip.empty?
            return {
              response_type: 'ephemeral',
              text: "Please provide an entry ID to delete. Usage: `/delete [ID]`\n\nYou can find entry IDs using `/log`"
            }.to_json
          end

          entry_id = text.strip.to_i
          
          if entry_id <= 0
            return {
              response_type: 'ephemeral',
              text: "Invalid entry ID: #{text}. Please provide a valid numeric ID."
            }.to_json
          end

          # Find the entry
          entry = Models::TimeEntry[entry_id]
          
          unless entry
            return {
              response_type: 'ephemeral',
              text: "Entry ##{entry_id} not found."
            }.to_json
          end

          # Check authorization: user can delete their own entries, admins can delete any
          user = Services::UserService.find_or_create(user_id)
          is_admin = authorized_for_team_report?(user_id)
          is_owner = entry.user_id == user.id

          unless is_owner || is_admin
            return {
              response_type: 'ephemeral',
              text: "You don't have permission to delete this entry. You can only delete your own entries."
            }.to_json
          end

          # Get entry details for confirmation message
          entry_user = entry.user
          project = entry.project
          hours = entry.hours
          date = entry.date
          notes = entry.notes || '—'

          # Delete the entry
          entry.destroy

          # Send confirmation
          {
            response_type: 'ephemeral',
            text: "✅ Deleted entry ##{entry_id}:\n• *#{date}* | @#{entry_user.slack_username} | *#{project.name}* | #{hours}h | #{notes}"
          }.to_json
        end

        def authorized_for_team_report?(user_id)
          admins = ENV.fetch('REPORT_ADMINS', '').split(',').map(&:strip)
          admins.include?(user_id)
        end

        def parse_days_argument(text)
          return 60 if text.nil? || text.strip.empty?

          days = text.strip.to_i
          
          # Validate: must be positive and reasonable (max 365)
          if days <= 0 || days > 365
            $logger.warn("Invalid days argument: #{text}, using default 60")
            return 60
          end
          
          days
        end

        def parse_month_argument(text)
          return Date.today if text.empty?

          # Try to parse YYYY-MM format
          if text =~ /^\d{4}-\d{2}$/
            year, month = text.split('-').map(&:to_i)
            return Date.new(year, month, 1)
          end

          # Try to parse YYYY-MM-DD format (use first of month)
          if text =~ /^\d{4}-\d{2}-\d{2}$/
            date = Date.parse(text)
            return Date.new(date.year, date.month, 1)
          end

          # Default to current month
          $logger.warn("Could not parse month argument: #{text}, using current month")
          Date.today
        rescue ArgumentError => e
          $logger.warn("Invalid date argument: #{text} - #{e.message}")
          Date.today
        end
      end
    end
  end
end
