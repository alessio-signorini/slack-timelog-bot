# frozen_string_literal: true

module TimelogBot
  module Services
    class UserService
      class << self
        # Get or create user with timezone info from Slack
        def find_or_create(slack_user_id)
          # Check if we already have this user cached
          user = Models::User.find(slack_user_id: slack_user_id)
          
          if user
            # Refresh timezone periodically (once per day)
            if user.updated_at && user.updated_at < Time.now - 86400
              refresh_timezone(user)
            end
            return user
          end

          # New user - fetch info from Slack
          slack_info = SlackClient.get_user_info(slack_user_id)
          
          if slack_info
            Models::User.create(
              slack_user_id: slack_user_id,
              slack_username: slack_info.profile&.display_name || slack_info.name,
              timezone: slack_info.tz || ENV.fetch('DEFAULT_TIMEZONE', 'America/Los_Angeles'),
              is_bot: slack_info.is_bot || false
            )
          else
            # Fallback if we can't get Slack info
            Models::User.create(
              slack_user_id: slack_user_id,
              timezone: ENV.fetch('DEFAULT_TIMEZONE', 'America/Los_Angeles'),
              is_bot: false
            )
          end
        end

        # Check if a Slack user ID is valid (not deleted, not a bot)
        def valid_slack_user?(slack_user_id)
          return false unless slack_user_id&.start_with?('U')
          
          # Check database first
          db_user = DB[:users].where(slack_user_id: slack_user_id).first
          return false if db_user && db_user[:is_bot]
          
          # Fetch from Slack API
          slack_info = SlackClient.get_user_info(slack_user_id)
          return false unless slack_info
          return false if slack_info.deleted
          
          # If it's a bot, mark it in the database for future checks
          if slack_info.is_bot
            DB[:users].insert_conflict(
              target: :slack_user_id,
              update: { is_bot: true, updated_at: Sequel::CURRENT_TIMESTAMP }
            ).insert(
              slack_user_id: slack_user_id,
              slack_username: slack_info.profile&.display_name || slack_info.name,
              is_bot: true,
              created_at: Sequel::CURRENT_TIMESTAMP,
              updated_at: Sequel::CURRENT_TIMESTAMP
            )
            return false
          end
          
          true
        end

        # Get user's current local time
        def local_time_for(user)
          require 'time'
          
          tz_name = user.timezone || ENV.fetch('DEFAULT_TIMEZONE', 'America/Los_Angeles')
          
          # Use TZInfo if available, otherwise fallback to UTC offset approximation
          begin
            require 'tzinfo'
            tz = TZInfo::Timezone.get(tz_name)
            tz.now
          rescue LoadError, TZInfo::InvalidTimezoneIdentifier
            # Fallback: just return current UTC time with timezone note
            $logger.warn("Could not convert timezone #{tz_name}, using UTC")
            Time.now.utc
          end
        end

        private

        def refresh_timezone(user)
          slack_info = SlackClient.get_user_info(user.slack_user_id)
          return unless slack_info

          new_tz = slack_info.tz
          if new_tz && new_tz != user.timezone
            user.update(timezone: new_tz)
            $logger.debug("Updated timezone for #{user.slack_user_id} to #{new_tz}")
          else
            # Touch updated_at even if timezone unchanged
            user.update(updated_at: Time.now)
          end
        rescue StandardError => e
          $logger.warn("Failed to refresh timezone for #{user.slack_user_id}: #{e.message}")
        end
      end
    end
  end
end
