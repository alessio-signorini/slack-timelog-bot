# frozen_string_literal: true

module TimelogBot
  module Handlers
    class EventHandler
      class << self
        def handle(event)
          inner_event = event['event']
          return unless inner_event

          # Ignore bot messages to prevent loops - check BEFORE recording
          return if inner_event['bot_id']

          # Deduplicate events using event_id - record BEFORE processing to prevent race conditions
          event_id = event['event_id']
          event_type = inner_event['type']
          original_message = inner_event['text']
          
          if event_id
            # Try to record the event first - this prevents race conditions
            event_log_id = record_event_processed(event_id, event_type, original_message)
            unless event_log_id
              $logger.info("Skipping duplicate event: #{event_id}")
              return
            end
            # Store event_log_id in thread-local storage for use when creating time entries
            Thread.current[:current_event_log_id] = event_log_id
          end

          $logger.debug("Handling event type: #{event_type}")

          case event_type
          when 'app_mention'
            handle_app_mention(inner_event)
          when 'message'
            handle_message(inner_event)
          else
            $logger.debug("Ignoring unhandled event type: #{event_type}")
          end
        rescue StandardError => e
          $logger.error("Error handling event: #{e.message}")
          $logger.error(e.backtrace.first(5).join("\n"))
        ensure
          Thread.current[:current_event_log_id] = nil
        end

        private

        def handle_app_mention(event)
          process_time_log_message(event)
        end

        def handle_message(event)
          # Only handle DMs (im type)
          return unless event['channel_type'] == 'im'
          
          # Ignore message subtypes (edits, deletes, etc)
          return if event['subtype']

          process_time_log_message(event)
        end

        def process_time_log_message(event)
          text = event['text']
          user_id = event['user']
          channel = event['channel']
          message_ts = event['ts']

          $logger.info("Processing time log from #{user_id}: #{text}")

          # Get user with timezone
          user = Services::UserService.find_or_create(user_id)

          # Parse the message using LLM
          result = Services::MessageParser.parse(
            text: text,
            user_timezone: user.timezone,
            requesting_user_id: user_id
          )

          if result[:error]
            # LLM or parsing error - send friendly message
            Services::SlackClient.post_ephemeral(
              channel: channel,
              user: user_id,
              text: result[:error]
            )
            return
          end

          if result[:needs_project_selection]
            # Low confidence on project - show interactive dropdown
            # Store parsed data in event_logs for retrieval after interaction
            store_pending_data(
              message_ts: message_ts,
              channel: channel,
              user_id: user_id,
              parsed_data: result[:parsed_data],
              original_message: text
            )
            
            send_project_selection(
              channel: channel,
              user_id: user_id,
              message_ts: message_ts,
              suggested_project: result[:suggested_project]
            )
            return
          end

          if result[:unknown_users]&.any?
            # Some mentioned users are invalid
            unknown = result[:unknown_users].join(', ')
            Services::SlackClient.post_ephemeral(
              channel: channel,
              user: user_id,
              text: "I couldn't find these users: #{unknown}. Please check the mentions and try again."
            )
            return
          end

          # All good - create time entries
          create_time_entries(
            entries: result[:entries],
            logged_by: user_id,
            channel: channel,
            message_ts: message_ts
          )
        end

        def send_project_selection(channel:, user_id:, message_ts:, suggested_project:)
          projects = Models::Project.all_names.sort
          
          options = projects.map do |name|
            {
              text: { type: 'plain_text', text: name },
              value: name
            }
          end

          # Add "Create New Project" option
          options << {
            text: { type: 'plain_text', text: '➕ Create New Project' },
            value: '__NEW_PROJECT__'
          }

          blocks = [
            {
              type: 'section',
              text: {
                type: 'mrkdwn',
                text: "I'm not sure which project you meant#{suggested_project ? " (did you mean *#{suggested_project}*?)" : ''}. Please select one:"
              }
            },
            {
              type: 'actions',
              block_id: "project_selection_#{message_ts}",  # Include message_ts for correlation
              elements: [
                {
                  type: 'static_select',
                  placeholder: {
                    type: 'plain_text',
                    text: 'Select a project...'
                  },
                  action_id: 'select_project',
                  options: options
                }
              ]
            }
          ]

          Services::SlackClient.post_ephemeral(
            channel: channel,
            user: user_id,
            text: 'Please select a project',
            blocks: blocks
          )
        end

        def create_time_entries(entries:, logged_by:, channel:, message_ts:)
          event_log_id = Thread.current[:current_event_log_id]
          
          entries.each do |entry|
            # Find or create user for the entry
            user = Services::UserService.find_or_create(entry[:user_id])
            
            # Find or create project
            project = Models::Project.find_or_create_by_name(entry[:project])

            # Create time entry
            Models::TimeEntry.create(
              user_id: user.id,
              project_id: project.id,
              minutes: entry[:minutes],
              date: entry[:date],
              notes: entry[:notes],
              logged_by_slack_id: logged_by,
              event_log_id: event_log_id
            )

            $logger.debug("Created time entry: #{user.slack_user_id} - #{entry[:minutes]}min on #{project.name}")
          end

          # Add checkmark reaction
          Services::SlackClient.add_reaction(
            channel: channel,
            timestamp: message_ts,
            emoji: 'white_check_mark'
          )

          $logger.info("Created #{entries.length} time entries")
        end

        def record_event_processed(event_id, event_type, original_message)
          result = DB[:event_logs].insert(
            event_id: event_id,
            event_type: event_type,
            original_message: original_message,
            processed_at: Time.now
          )
          result  # Returns the inserted row ID
        rescue Sequel::UniqueConstraintViolation
          # Race condition: another thread already logged this event
          $logger.debug("Event #{event_id} already recorded by another thread")
          nil  # Already processed
        end

        def store_pending_data(message_ts:, channel:, user_id:, parsed_data:, original_message:)
          # Store parsed entry data for retrieval after interactive response
          pending_data = {
            entries: parsed_data[:entries],
            original_message: original_message,
            suggested_project_name: parsed_data[:suggested_project_name]
          }

          DB[:event_logs].insert(
            event_id: "pending_#{message_ts}",
            event_type: 'pending_project_selection',
            message_ts: message_ts,
            channel_id: channel,
            user_id: user_id,
            pending_data: Oj.dump(pending_data, mode: :compat),
            processed_at: Time.now
          )

          $logger.debug("Stored pending data for message_ts: #{message_ts}")
        rescue Sequel::UniqueConstraintViolation
          # Already stored, update it
          DB[:event_logs]
            .where(message_ts: message_ts)
            .update(
              pending_data: Oj.dump(pending_data, mode: :compat),
              processed_at: Time.now
            )
        end
      end
    end
  end
end
