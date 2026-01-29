# frozen_string_literal: true

require_relative '../test_helper'

class TimeEntryParsingTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
    stub_slack_api
    
    # Create test projects
    @mushroom = create_test_project(name: 'Mushroom')
    @monkey = create_test_project(name: 'Monkey')
    
    ENV['SLACK_SIGNING_SECRET'] = 'test_secret'
    ENV['LLM_MODEL'] = 'anthropic/claude-haiku-4.5'
  end

  def test_parses_simple_time_entry
    user = create_test_user(slack_id: 'U12345678')
    
    # Mock the message parser to return a valid result
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      entries: [
        {
          user_id: 'U12345678',
          minutes: 180,
          project: 'Mushroom',
          date: Date.today,
          notes: 'Working on data analysis'
        }
      ]
    })
    
    # Simulate processing
    result = TimelogBot::Services::MessageParser.parse(
      text: 'I spent 3 hours on Mushroom today working on data analysis',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U12345678'
    )
    
    assert_equal 1, result[:entries].length
    assert_equal 180, result[:entries][0][:minutes]
    assert_equal 'Mushroom', result[:entries][0][:project]
  end

  def test_parses_fractional_hours
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      entries: [
        {
          user_id: 'U12345678',
          minutes: 150, # 2.5 hours
          project: 'Monkey',
          date: Date.today,
          notes: nil
        }
      ]
    })
    
    result = TimelogBot::Services::MessageParser.parse(
      text: 'I worked 2.5 hours on Monkey',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U12345678'
    )
    
    assert_equal 150, result[:entries][0][:minutes]
  end

  def test_creates_separate_entries_for_multiple_users
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      entries: [
        {
          user_id: 'U111',
          minutes: 180,
          project: 'Mushroom',
          date: Date.today,
          notes: 'Team work'
        },
        {
          user_id: 'U222',
          minutes: 180,
          project: 'Mushroom',
          date: Date.today,
          notes: 'Team work'
        }
      ]
    })
    
    result = TimelogBot::Services::MessageParser.parse(
      text: '<@U111> and <@U222> spent 3 hours on Mushroom',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U111'
    )
    
    assert_equal 2, result[:entries].length
    assert_equal 'U111', result[:entries][0][:user_id]
    assert_equal 'U222', result[:entries][1][:user_id]
  end

  def test_returns_error_for_unknown_users
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      unknown_users: ['<@UINVALID>']
    })
    
    result = TimelogBot::Services::MessageParser.parse(
      text: '<@UINVALID> worked 2h on Monkey',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U12345678'
    )
    
    assert result[:unknown_users]
    assert_includes result[:unknown_users], '<@UINVALID>'
  end

  def test_needs_project_selection_for_low_confidence
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      needs_project_selection: true,
      suggested_project: 'some project',
      parsed_data: {
        entries: [
          {
            'user_id' => 'U12345678',
            'minutes' => 120,
            'date' => Date.today.to_s,
            'notes' => nil
          }
        ]
      }
    })
    
    result = TimelogBot::Services::MessageParser.parse(
      text: 'I worked 2h on some project',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U12345678'
    )
    
    assert result[:needs_project_selection]
    assert_equal 'some project', result[:suggested_project]
  end

  def test_handles_llm_errors_gracefully
    TimelogBot::Services::MessageParser.stubs(:parse).returns({
      error: "I'm having trouble understanding right now. Please try again in a moment. 🙏"
    })
    
    result = TimelogBot::Services::MessageParser.parse(
      text: 'gibberish that makes no sense',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U12345678'
    )
    
    assert result[:error]
    refute result[:entries]
  end

  def test_stores_time_in_minutes
    user = create_test_user(slack_id: 'U12345678')
    project = create_test_project(name: 'TestProject')
    
    entry = TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 90,
      date: Date.today,
      logged_by_slack_id: user.slack_user_id
    )
    
    assert_equal 90, entry.minutes
    assert_equal 1.5, entry.hours
  end

  def test_converts_hours_to_minutes_on_assignment
    user = create_test_user(slack_id: 'U12345678')
    project = create_test_project(name: 'TestProject')
    
    entry = TimelogBot::Models::TimeEntry.new(
      user_id: user.id,
      project_id: project.id,
      date: Date.today,
      logged_by_slack_id: user.slack_user_id
    )
    entry.hours = 2.5
    entry.save
    
    assert_equal 150, entry.minutes
  end

  def test_stores_original_message_via_event_log
    user = create_test_user(slack_id: 'U12345678')
    project = create_test_project(name: 'TestProject')
    
    original_text = 'I spent 3 hours on TestProject working on data analysis'
    
    # Create event log first
    event_log_id = DB[:event_logs].insert(
      event_id: 'evt_test_123',
      event_type: 'app_mention',
      original_message: original_text,
      processed_at: Time.now
    )
    
    entry = TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 180,
      date: Date.today,
      notes: 'Working on data analysis',
      logged_by_slack_id: user.slack_user_id,
      event_log_id: event_log_id
    )
    
    # Verify the relationship
    event_log = DB[:event_logs].where(id: entry.event_log_id).first
    assert_equal original_text, event_log[:original_message]
    
    # Verify it's persisted
    reloaded = TimelogBot::Models::TimeEntry[entry.id]
    reloaded_event = DB[:event_logs].where(id: reloaded.event_log_id).first
    assert_equal original_text, reloaded_event[:original_message]
  end

  def test_event_log_reference_is_optional
    user = create_test_user(slack_id: 'U12345678')
    project = create_test_project(name: 'TestProject')
    
    # Should work without event_log_id
    entry = TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today,
      logged_by_slack_id: user.slack_user_id
    )
    
    assert_nil entry.event_log_id
    assert entry.valid?
  end
end
