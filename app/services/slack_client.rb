# frozen_string_literal: true

require 'slack-ruby-client'

module TimelogBot
  module Services
    class SlackClient
      class << self
        def client
          @client ||= begin
            Slack.configure do |config|
              config.token = ENV.fetch('SLACK_BOT_TOKEN')
            end
            Slack::Web::Client.new
          end
        end

        # Add emoji reaction to a message
        def add_reaction(channel:, timestamp:, emoji: 'white_check_mark')
          client.reactions_add(
            channel: channel,
            timestamp: timestamp,
            name: emoji
          )
        rescue Slack::Web::Api::Errors::AlreadyReacted
          # Ignore if already reacted
          $logger.debug("Already reacted with #{emoji}")
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to add reaction: #{e.message}")
        end

        # Post ephemeral message (only visible to one user)
        def post_ephemeral(channel:, user:, text: nil, blocks: nil, attachments: nil)
          params = {
            channel: channel,
            user: user,
            text: text
          }
          params[:blocks] = blocks if blocks
          params[:attachments] = attachments if attachments

          client.chat_postEphemeral(**params)
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to post ephemeral message: #{e.message}")
          raise
        end

        # Post message to channel
        def post_message(channel:, text: nil, blocks: nil, thread_ts: nil)
          params = {
            channel: channel,
            text: text
          }
          params[:blocks] = blocks if blocks
          params[:thread_ts] = thread_ts if thread_ts

          client.chat_postMessage(**params)
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to post message: #{e.message}")
          raise
        end

        # Get user info including timezone
        def get_user_info(user_id)
          response = client.users_info(user: user_id)
          response.user
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to get user info for #{user_id}: #{e.message}")
          nil
        end

        # Get the bot's own user ID
        # Checks database first (persists across restarts), falls back to API on first boot
        def bot_user_id
          @bot_user_id ||= begin
            # Check if we have a bot user in the database
            bot_user = DB[:users].where(is_bot: true).first
            
            if bot_user
              $logger.debug("Bot user ID loaded from database: #{bot_user[:slack_user_id]}")
              bot_user[:slack_user_id]
            else
              # First boot - fetch from Slack API and store in database
              $logger.debug("Bot user not in database, fetching from Slack API")
              response = client.auth_test
              bot_id = response.user_id
              
              # Store bot in database for future boots
              DB[:users].insert_conflict(
                target: :slack_user_id,
                update: { is_bot: true, updated_at: Sequel::CURRENT_TIMESTAMP }
              ).insert(
                slack_user_id: bot_id,
                slack_username: response.user,
                is_bot: true,
                created_at: Sequel::CURRENT_TIMESTAMP,
                updated_at: Sequel::CURRENT_TIMESTAMP
              )
              
              $logger.info("Bot user ID detected and stored in database: #{bot_id}")
              bot_id
            end
          rescue Slack::Web::Api::Errors::SlackError => e
            $logger.error("Failed to get bot user ID: #{e.message}")
            nil
          end
        end

        # Open a modal view
        def open_modal(trigger_id:, view:)
          client.views_open(
            trigger_id: trigger_id,
            view: view
          )
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to open modal: #{e.message}")
          raise
        end

        # Update a modal view
        def update_modal(view_id:, view:)
          client.views_update(
            view_id: view_id,
            view: view
          )
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to update modal: #{e.message}")
          raise
        end

        # Upload a file (for CSV reports)
        def upload_file(channel:, content:, filename:, title: nil, initial_comment: nil)
          client.files_upload_v2(
            channel: channel,
            content: content,
            filename: filename,
            title: title || filename,
            initial_comment: initial_comment
          )
        rescue Slack::Web::Api::Errors::SlackError => e
          $logger.error("Failed to upload file: #{e.message}")
          raise
        end

        # Post to Slack response_url (for async slash command responses)
        def post_to_response_url(response_url, payload)
          require 'net/http'
          require 'uri'
          require 'json'

          uri = URI.parse(response_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Post.new(uri.path)
          request['Content-Type'] = 'application/json'
          request.body = payload.to_json

          response = http.request(request)
          
          unless response.code == '200'
            $logger.error("Failed to post to response_url: #{response.code} #{response.body}")
          end
        rescue StandardError => e
          $logger.error("Failed to post to response_url: #{e.message}")
        end
      end
    end
  end
end
