# frozen_string_literal: true

require_relative '../test_helper'

class InteractiveContextTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
    stub_slack_api
  end

  def test_pending_data_is_stored_when_project_needs_selection
    message_ts = '1234567890.123456'
    channel = 'C123'
    user_id = 'U123'
    
    # Create user
    TimelogBot::Models::User.create(
      slack_user_id: user_id,
      slack_username: 'testuser',
      timezone: 'America/Los_Angeles'
    )

    # Mock LLM to return low confidence project
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      needs_project_selection: true,
      suggested_project: 'Unknown Project',
      parsed_data: {
        entries: [
          {
            user_id: user_id,
            minutes: 120,
            project: nil,
            date: Date.today.to_s,
            notes: 'Work on stuff'
          }
        ],
        suggested_project_name: 'Unknown Project'
      }
    })

    event = {
      'event' => {
        'type' => 'app_mention',
        'user' => user_id,
        'text' => 'I worked 2 hours on Unknown Project',
        'channel' => channel,
        'ts' => message_ts
      }
    }

    # Process the event
    TimelogBot::Handlers::EventHandler.handle(event)

    # Verify pending data was stored
    pending = DB[:event_logs]
      .where(message_ts: message_ts, event_type: 'pending_project_selection')
      .first

    assert pending, 'Pending data should be stored'
    assert_equal channel, pending[:channel_id]
    assert_equal user_id, pending[:user_id]
    
    pending_data = Oj.load(pending[:pending_data], symbol_keys: true)
    assert_equal 1, pending_data[:entries].length
    assert_equal user_id, pending_data[:entries][0][:user_id]
    assert_equal 120, pending_data[:entries][0][:minutes]
    assert_equal 'I worked 2 hours on Unknown Project', pending_data[:original_message]
  end

  def test_interactive_handler_retrieves_pending_data_and_creates_entries
    message_ts = '2234567890.234567'  # Unique timestamp
    channel = 'C456'
    user_id = 'U456TEST'
    
    # Create user and project
    TimelogBot::Models::User.create(
      slack_user_id: user_id,
      slack_username: 'testuser2',
      timezone: 'America/Los_Angeles'
    )
    TimelogBot::Models::Project.create(name: 'Waterfall')

    # Store pending data
    pending_data = {
      entries: [
        {
          user_id: user_id,
          minutes: 180,
          project: nil,
          date: Date.today.to_s,
          notes: 'Working on tasks'
        }
      ],
      original_message: 'I worked 3 hours on stuff',
      suggested_project_name: 'stuff'
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

    # Simulate interactive payload
    payload = {
      'type' => 'block_actions',
      'user' => { 'id' => user_id },
      'channel' => { 'id' => channel },
      'actions' => [
        {
          'action_id' => 'select_project',
          'block_id' => "project_selection_#{message_ts}",
          'selected_option' => { 'value' => 'Waterfall' }
        }
      ]
    }

    initial_entries = DB[:time_entries].count

    # Handle the interaction
    TimelogBot::Handlers::InteractiveHandler.handle(payload)

    # Verify time entry was created
    assert_equal initial_entries + 1, DB[:time_entries].count
    
    entry = DB[:time_entries].order(:id).last
    assert_equal 180, entry[:minutes]
    assert_equal Date.today, entry[:date]
    
    # Verify original_message is stored in event_log
    event_log = DB[:event_logs].where(id: entry[:event_log_id]).first
    assert event_log, 'Event log should exist'
    assert_equal 'I worked 3 hours on stuff', event_log[:original_message]

    # Verify pending data was cleaned up
    pending = DB[:event_logs]
      .where(message_ts: message_ts, event_type: 'pending_project_selection')
      .first
    assert_nil pending, 'Pending data should be cleaned up after processing'
  end

  def test_create_new_project_from_modal_with_pending_data
    message_ts = '3234567890.345678'  # Unique timestamp
    channel = 'C789'
    user_id = 'U789TEST'
    
    # Create user
    TimelogBot::Models::User.create(
      slack_user_id: user_id,
      slack_username: 'testuser3',
      timezone: 'America/Los_Angeles'
    )

    # Store pending data
    pending_data = {
      entries: [
        {
          user_id: user_id,
          minutes: 240,
          project: nil,
          date: Date.today.to_s,
          notes: 'New project work'
        }
      ],
      original_message: 'I worked 4 hours on NewProj',
      suggested_project_name: 'NewProj'
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

    # Simulate modal submission
    payload = {
      'type' => 'view_submission',
      'user' => { 'id' => user_id },
      'view' => {
        'callback_id' => 'create_project_modal',
        'private_metadata' => Oj.dump({ message_ts: message_ts }, mode: :compat),
        'state' => {
          'values' => {
            'project_name_block' => {
              'project_name_input' => {
                'value' => 'NewProj'
              }
            }
          }
        }
      }
    }

    initial_projects = DB[:projects].count
    initial_entries = DB[:time_entries].count

    # Handle the modal submission
    TimelogBot::Handlers::InteractiveHandler.handle(payload)

    # Verify project was created
    assert_equal initial_projects + 1, DB[:projects].count
    project = DB[:projects].where(name: 'NewProj').first
    assert project, 'Project should be created'

    # Verify time entry was created
    assert_equal initial_entries + 1, DB[:time_entries].count
    entry = DB[:time_entries].order(:id).last
    assert_equal 240, entry[:minutes]
    assert_equal project[:id], entry[:project_id]
    
    # Verify original_message is stored in event_log
    event_log = DB[:event_logs].where(id: entry[:event_log_id]).first
    assert event_log, 'Event log should exist'
    assert_equal 'I worked 4 hours on NewProj', event_log[:original_message]

    # Verify pending data was cleaned up
    pending = DB[:event_logs]
      .where(message_ts: message_ts, event_type: 'pending_project_selection')
      .first
    assert_nil pending, 'Pending data should be cleaned up'
  end

  def test_handles_missing_pending_data_gracefully
    message_ts = '9999999999.999999'
    channel = 'C999'
    user_id = 'U999'
    
    TimelogBot::Models::User.create(
      slack_user_id: user_id,
      slack_username: 'testuser4',
      timezone: 'America/Los_Angeles'
    )

    # Simulate interaction without pending data
    payload = {
      'type' => 'block_actions',
      'user' => { 'id' => user_id },
      'channel' => { 'id' => channel },
      'actions' => [
        {
          'action_id' => 'select_project',
          'block_id' => "project_selection_#{message_ts}",
          'selected_option' => { 'value' => 'SomeProject' }
        }
      ]
    }

    # Should not raise error, but will log error (suppress it)
    suppress_logging do
      TimelogBot::Handlers::InteractiveHandler.handle(payload)
    end

    # Should have posted error message to user (via stub)
    # No exception should be raised
  end
end
