# frozen_string_literal: true

module TimelogBot
  module Models
    class User < Sequel::Model(DB[:users])
      one_to_many :time_entries

      plugin :timestamps, update_on_create: true

      def before_save
        self.updated_at = Time.now
        super
      end

      def self.find_or_create_by_slack_id(slack_user_id, username: nil, timezone: nil)
        user = find(slack_user_id: slack_user_id)
        
        if user
          # Update timezone if provided and different
          if timezone && user.timezone != timezone
            user.update(timezone: timezone)
          end
          user
        else
          create(
            slack_user_id: slack_user_id,
            slack_username: username,
            timezone: timezone || ENV.fetch('DEFAULT_TIMEZONE', 'America/Los_Angeles')
          )
        end
      end

      def display_name
        slack_username || slack_user_id
      end
    end
  end
end
