# frozen_string_literal: true

require_relative '../test_helper'

class EventDeduplicationTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
    stub_slack_api
  end

  def test_duplicate_events_are_processed_only_once
    event_id = 'Ev12345TEST'
    slack_event = {
      'event_id' => event_id,
      'event' => {
        'type' => 'app_mention',
        'user' => 'U123',
        'text' => '<@BOTID> I worked 2 hours on Waterfall today',
        'channel' => 'C123',
        'ts' => '1234567890.123456'
      }
    }

    # Create necessary test data
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U123',
      slack_username: 'testuser',
      timezone: 'America/Los_Angeles'
    )
    project = TimelogBot::Models::Project.create(name: 'Waterfall')

    # Mock the LLM response
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      entries: [
        {
          user_id: 'U123',
          minutes: 120,
          project: 'Waterfall',
          date: Date.today,
          notes: 'Working on tasks'
        }
      ]
    })

    # Get initial counts
    initial_entries = DB[:time_entries].count
    initial_events = DB[:event_logs].count

    # First event - should be processed
    TimelogBot::Handlers::EventHandler.handle(slack_event)

    # Verify entry was created
    assert_equal initial_entries + 1, DB[:time_entries].count
    assert_equal initial_events + 1, DB[:event_logs].count

    # Verify event was logged
    event_log = DB[:event_logs].where(event_id: event_id).first
    assert event_log, 'Event log should exist'
    assert_equal event_id, event_log[:event_id]
    assert_equal 'app_mention', event_log[:event_type]

    # Second event with same event_id - should be skipped (suppress duplicate log)
    suppress_logging do
      TimelogBot::Handlers::EventHandler.handle(slack_event)
    end

    # Verify no new entries were created
    assert_equal initial_entries + 1, DB[:time_entries].count
    assert_equal initial_events + 1, DB[:event_logs].count
  end

  def test_different_events_are_processed_separately
    slack_event1 = {
      'event_id' => 'Ev12345DIFF1',
      'event' => {
        'type' => 'app_mention',
        'user' => 'U456',
        'text' => '<@BOTID> I worked 2 hours on Waterfall',
        'channel' => 'C123',
        'ts' => '1234567890.123456'
      }
    }

    slack_event2 = {
      'event_id' => 'Ev67890DIFF2',  # Different event_id
      'event' => {
        'type' => 'app_mention',
        'user' => 'U456',
        'text' => '<@BOTID> I worked 3 hours on Mushroom',
        'channel' => 'C123',
        'ts' => '1234567890.123457'
      }
    }

    # Create test data
    TimelogBot::Models::User.create(
      slack_user_id: 'U456',
      slack_username: 'testuser2',
      timezone: 'America/Los_Angeles'
    )
    TimelogBot::Models::Project.create(name: 'Waterfall')
    TimelogBot::Models::Project.create(name: 'Mushroom')

    # Track call count for parse
    call_count = 0
    TimelogBot::Services::MessageParser.stubs(:parse).with { call_count += 1; true }.returns(
      proc do
        if call_count == 1
          {
            entries: [
              {
                user_id: 'U456',
                minutes: 120,
                project: 'Waterfall',
                date: Date.today,
                notes: 'Work'
              }
            ]
          }
        else
          {
            entries: [
              {
                user_id: 'U456',
                minutes: 180,
                project: 'Mushroom',
                date: Date.today,
                notes: 'Work'
              }
            ]
          }
        end
      end.call
    )

    # Get initial counts
    initial_entries = DB[:time_entries].count
    initial_events = DB[:event_logs].count

    # Process both events
    TimelogBot::Handlers::EventHandler.handle(slack_event1)
    TimelogBot::Handlers::EventHandler.handle(slack_event2)

    # Both should be processed
    assert_equal initial_entries + 2, DB[:time_entries].count
    assert_equal initial_events + 2, DB[:event_logs].count
  end

  def test_events_without_event_id_are_still_processed
    # Some events might not have an event_id (edge case)
    slack_event = {
      'event' => {
        'type' => 'app_mention',
        'user' => 'U789',
        'text' => '<@BOTID> I worked 2 hours on Waterfall',
        'channel' => 'C123',
        'ts' => '1234567890.123456'
      }
    }

    TimelogBot::Models::User.create(
      slack_user_id: 'U789',
      slack_username: 'testuser3',
      timezone: 'America/Los_Angeles'
    )
    TimelogBot::Models::Project.create(name: 'Waterfall')

    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      entries: [
        {
          user_id: 'U789',
          minutes: 120,
          project: 'Waterfall',
          date: Date.today,
          notes: 'Work'
        }
      ]
    })

    initial_entries = DB[:time_entries].count
    initial_events = DB[:event_logs].count

    # Should process without error
    TimelogBot::Handlers::EventHandler.handle(slack_event)

    assert_equal initial_entries + 1, DB[:time_entries].count
    assert_equal initial_events, DB[:event_logs].count  # No event_id to log
  end

  def test_bot_messages_are_ignored_and_not_logged
    # Bot's own messages should be filtered out before being recorded
    bot_event = {
      'event_id' => 'Ev_BOT_MESSAGE',
      'event' => {
        'type' => 'message',
        'bot_id' => 'B123BOT',  # This identifies it as a bot message
        'user' => 'U_BOT',
        'text' => "Here's your time report!",
        'channel' => 'C123',
        'channel_type' => 'im',
        'ts' => '1234567890.123456'
      }
    }

    initial_entries = DB[:time_entries].count
    initial_events = DB[:event_logs].count

    # Process bot event
    TimelogBot::Handlers::EventHandler.handle(bot_event)

    # Verify nothing was created - bot messages should be completely ignored
    assert_equal initial_entries, DB[:time_entries].count, 'No time entries should be created for bot messages'
    assert_equal initial_events, DB[:event_logs].count, 'Bot messages should not be logged in event_logs'
  end

  def test_bot_app_mentions_are_ignored_and_not_logged
    # Bot's own app mentions should also be filtered out
    bot_mention_event = {
      'event_id' => 'Ev_BOT_MENTION',
      'event' => {
        'type' => 'app_mention',
        'bot_id' => 'B123BOT',  # This identifies it as a bot message
        'user' => 'U_BOT',
        'text' => '<@BOTID> automatic response',
        'channel' => 'C123',
        'ts' => '1234567890.123456'
      }
    }

    initial_entries = DB[:time_entries].count
    initial_events = DB[:event_logs].count

    # Process bot event
    TimelogBot::Handlers::EventHandler.handle(bot_mention_event)

    # Verify nothing was created - bot mentions should be completely ignored
    assert_equal initial_entries, DB[:time_entries].count, 'No time entries should be created for bot app mentions'
    assert_equal initial_events, DB[:event_logs].count, 'Bot app mentions should not be logged in event_logs'
  end
end
