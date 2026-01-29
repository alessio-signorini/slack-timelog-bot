# frozen_string_literal: true

module TimelogBot
  module Handlers
    class InteractiveHandler
      class << self
        def handle(payload)
          type = payload['type']
          $logger.debug("Handling interactive payload type: #{type}")

          case type
          when 'block_actions'
            handle_block_actions(payload)
          when 'view_submission'
            handle_view_submission(payload)
          else
            $logger.debug("Ignoring unhandled interactive type: #{type}")
            nil
          end
        rescue StandardError => e
          $logger.error("Error handling interactive: #{e.message}")
          $logger.error(e.backtrace.first(5).join("\n"))
          nil
        end

        private

        def handle_block_actions(payload)
          actions = payload['actions']
          return unless actions&.any?

          action = actions.first
          action_id = action['action_id']

          case action_id
          when 'select_project'
            handle_project_selection(payload, action)
          else
            $logger.debug("Ignoring unhandled action: #{action_id}")
          end
        end

        def handle_project_selection(payload, action)
          selected_value = action.dig('selected_option', 'value')
          user_id = payload.dig('user', 'id')
          channel = payload.dig('channel', 'id')
          trigger_id = payload['trigger_id']

          # Extract message_ts from block_id (format: "project_selection_1234567890.123456")
          block_id = action['block_id']
          message_ts = block_id.sub('project_selection_', '') if block_id&.start_with?('project_selection_')

          # Retrieve pending data from event_logs
          pending_data = retrieve_pending_data(message_ts)

          unless pending_data
            $logger.error("No pending data found for message_ts: #{message_ts}")
            Services::SlackClient.post_ephemeral(
              channel: channel,
              user: user_id,
              text: "Sorry, I lost track of that request. Please try logging your time again."
            )
            return
          end

          if selected_value == '__NEW_PROJECT__'
            # Open modal for new project creation
            open_new_project_modal(
              trigger_id: trigger_id,
              pending_data: pending_data,
              message_ts: message_ts,
              suggested_name: pending_data['suggested_project_name']
            )
          else
            # Create time entries with selected project
            create_entries_with_project(
              project_name: selected_value,
              pending_data: pending_data,
              user_id: user_id,
              channel: channel,
              message_ts: message_ts
            )
            
            # Clean up pending data
            cleanup_pending_data(message_ts)
          end

          nil
        end

        def open_new_project_modal(trigger_id:, pending_data:, message_ts:, suggested_name: nil)
          view = {
            type: 'modal',
            callback_id: 'create_project_modal',
            private_metadata: Oj.dump({ message_ts: message_ts }, mode: :compat),
            title: {
              type: 'plain_text',
              text: 'Create New Project'
            },
            submit: {
              type: 'plain_text',
              text: 'Create'
            },
            close: {
              type: 'plain_text',
              text: 'Cancel'
            },
            blocks: [
              {
                type: 'input',
                block_id: 'project_name_block',
                label: {
                  type: 'plain_text',
                  text: 'Project Name'
                },
                element: {
                  type: 'plain_text_input',
                  action_id: 'project_name_input',
                  placeholder: {
                    type: 'plain_text',
                    text: 'Enter project name...'
                  },
                  initial_value: suggested_name || ''
                }
              }
            ]
          }

          Services::SlackClient.open_modal(trigger_id: trigger_id, view: view)
        end

        def handle_view_submission(payload)
          callback_id = payload.dig('view', 'callback_id')
          
          case callback_id
          when 'create_project_modal'
            handle_create_project_submission(payload)
          else
            $logger.debug("Ignoring unhandled view submission: #{callback_id}")
            nil
          end
        end

        def handle_create_project_submission(payload)
          user_id = payload.dig('user', 'id')
          values = payload.dig('view', 'state', 'values')
          project_name = values.dig('project_name_block', 'project_name_input', 'value')&.strip

          # Validate project name
          if project_name.nil? || project_name.empty?
            return {
              response_action: 'errors',
              errors: {
                project_name_block: 'Project name is required'
              }
            }
          end

          # Check if project already exists
          existing = Models::Project.find_by_name(project_name)
          if existing
            return {
              response_action: 'errors',
              errors: {
                project_name_block: 'A project with this name already exists'
              }
            }
          end

          # Create the project
          project = Models::Project.create(name: project_name)
          $logger.info("Created new project: #{project_name}")

          # Get message_ts from private_metadata
          private_metadata = payload.dig('view', 'private_metadata')
          metadata = private_metadata ? Oj.load(private_metadata, symbol_keys: true) : {}
          message_ts = metadata[:message_ts]

          # Retrieve pending data
          pending_data = retrieve_pending_data(message_ts)

          if pending_data
            # Get channel from pending data
            channel = DB[:event_logs].where(message_ts: message_ts).select(:channel_id).first&.dig(:channel_id)
            
            # Create time entries with new project
            create_entries_with_project(
              project_name: project_name,
              pending_data: pending_data,
              user_id: user_id,
              channel: channel,
              message_ts: message_ts
            )
            
            # Clean up pending data
            cleanup_pending_data(message_ts)
          end

          # Close modal
          nil
        end

        def create_entries_with_project(project_name:, pending_data:, user_id:, channel:, message_ts:)
          return unless pending_data && pending_data['entries']

          project = Models::Project.find_or_create_by_name(project_name)
          original_message = pending_data['original_message']
          
          # Create or find event log for this interaction
          event_log_id = find_or_create_event_log(message_ts, original_message)

          pending_data['entries'].each do |entry|
            entry_user = Services::UserService.find_or_create(entry['user_id'])
            
            Models::TimeEntry.create(
              user_id: entry_user.id,
              project_id: project.id,
              minutes: entry['minutes'],
              date: Date.parse(entry['date']),
              notes: entry['notes'],
              logged_by_slack_id: user_id,
              event_log_id: event_log_id
            )

            $logger.debug("Created time entry: #{entry_user.slack_user_id} - #{entry['minutes']}min on #{project_name}")
          end

          # Add reaction to original message
          if message_ts && channel
            Services::SlackClient.add_reaction(
              channel: channel,
              timestamp: message_ts,
              emoji: 'white_check_mark'
            )
          end

          $logger.info("Created #{pending_data['entries'].length} time entries for project #{project_name}")
        end

        def retrieve_pending_data(message_ts)
          return nil unless message_ts

          row = DB[:event_logs]
            .where(message_ts: message_ts, event_type: 'pending_project_selection')
            .first

          return nil unless row && row[:pending_data]

          # Return with string keys to match expected format
          Oj.load(row[:pending_data])
        rescue StandardError => e
          $logger.error("Failed to retrieve pending data: #{e.message}")
          nil
        end

        def cleanup_pending_data(message_ts)
          return unless message_ts

          DB[:event_logs]
            .where(message_ts: message_ts, event_type: 'pending_project_selection')
            .delete

          $logger.debug("Cleaned up pending data for message_ts: #{message_ts}")
        end

        def find_or_create_event_log(message_ts, original_message)
          # Try to find existing event log by message_ts
          existing = DB[:event_logs]
            .where(message_ts: message_ts)
            .where(Sequel.~(event_type: 'pending_project_selection'))
            .first

          return existing[:id] if existing

          # Create a new event log for this interactive response
          DB[:event_logs].insert(
            event_id: "interactive_#{message_ts}",
            event_type: 'interactive_response',
            message_ts: message_ts,
            original_message: original_message,
            processed_at: Time.now
          )
        rescue Sequel::UniqueConstraintViolation
          # Already created, fetch it
          DB[:event_logs]
            .where(event_id: "interactive_#{message_ts}")
            .get(:id)
        end

        def extract_metadata(payload)
          # Try to get metadata from attachments
          attachments = payload['message']&.dig('attachments')
          return nil unless attachments&.any?

          metadata_json = attachments.first['metadata']
          return nil unless metadata_json

          Oj.load(metadata_json)
        rescue StandardError => e
          $logger.warn("Failed to extract metadata: #{e.message}")
          nil
        end
      end
    end
  end
end
