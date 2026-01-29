# frozen_string_literal: true

require_relative '../test_helper'

class LogCommandTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete
  end

  def test_log_command_returns_entries_for_last_60_days
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entries within last 60 days
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today - 10,
      notes: 'Working on feature A',
      logged_by_slack_id: 'U12345'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 180,
      date: Date.today - 30,
      notes: 'Bug fixes',
      logged_by_slack_id: 'U12345'
    )

    # Create entry outside 60 days (should not appear)
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 60,
      date: Date.today - 65,
      notes: 'Old work',
      logged_by_slack_id: 'U12345'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_equal 'ephemeral', result[:response_type]
    assert_includes result[:text], 'Your Time Entries (Last 60 Days)'
    assert_includes result[:text], 'Working on feature A'
    assert_includes result[:text], 'Bug fixes'
    assert_includes result[:text], '2.0h'
    assert_includes result[:text], '3.0h'
    assert_includes result[:text], 'Total:'
    assert_includes result[:text], '5.0h'
    refute_includes result[:text], 'Old work'
  end

  def test_log_command_shows_who_logged_the_entry
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create another user who logged for alice
    other_user = TimelogBot::Models::User.create(
      slack_user_id: 'U67890',
      slack_username: 'bob',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Entry logged by user themselves
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today - 5,
      notes: 'Self logged',
      logged_by_slack_id: 'U12345'
    )

    # Entry logged by someone else
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 180,
      date: Date.today - 3,
      notes: 'Logged by manager',
      logged_by_slack_id: 'U67890'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_includes result[:text], 'Logged by you'
    assert_includes result[:text], 'Logged by @bob'
  end

  def test_log_command_returns_message_when_no_entries
    # Create user with no entries
    TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_equal 'ephemeral', result[:response_type]
    assert_includes result[:text], "You don't have any time entries in the last 60 days"
  end

  def test_log_command_formats_entries_correctly
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entry with no notes
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 90,
      date: Date.today - 1,
      notes: nil,
      logged_by_slack_id: 'U12345'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    # Should show em dash for missing notes
    assert_includes result[:text], '—'
    assert_includes result[:text], '1.5h'
  end

  def test_log_command_orders_entries_by_date
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entries out of order
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 60,
      date: Date.today - 10,
      notes: 'Third',
      logged_by_slack_id: 'U12345'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 60,
      date: Date.today - 20,
      notes: 'First',
      logged_by_slack_id: 'U12345'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 60,
      date: Date.today - 15,
      notes: 'Second',
      logged_by_slack_id: 'U12345'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    # Check order in text
    text = result[:text]
    first_pos = text.index('First')
    second_pos = text.index('Second')
    third_pos = text.index('Third')

    assert first_pos < second_pos, 'First should appear before Second'
    assert second_pos < third_pos, 'Second should appear before Third'
  end

  def test_log_command_includes_project_name
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create multiple projects
    project1 = TimelogBot::Models::Project.create(name: 'ProjectA')
    project2 = TimelogBot::Models::Project.create(name: 'ProjectB')

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project1.id,
      minutes: 60,
      date: Date.today - 5,
      notes: 'Work on A',
      logged_by_slack_id: 'U12345'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project2.id,
      minutes: 120,
      date: Date.today - 3,
      notes: 'Work on B',
      logged_by_slack_id: 'U12345'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_includes result[:text], 'ProjectA'
    assert_includes result[:text], 'ProjectB'
  end

  def test_log_command_accepts_custom_days_parameter
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entry within 30 days
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today - 20,
      notes: 'Recent work',
      logged_by_slack_id: 'U12345'
    )

    # Create entry outside 30 days but within 60
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 180,
      date: Date.today - 45,
      notes: 'Older work',
      logged_by_slack_id: 'U12345'
    )

    # Request only last 30 days
    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => '30'
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_includes result[:text], 'Your Time Entries (Last 30 Days)'
    assert_includes result[:text], 'Recent work'
    refute_includes result[:text], 'Older work'
  end

  def test_log_command_validates_days_parameter
    # Create user with no entries
    TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Test with invalid days (negative)
    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => '-10'
    }

    result_json = suppress_logging do
      TimelogBot::Handlers::SlashCommandHandler.handle(params)
    end
    result = Oj.load(result_json, symbol_keys: true)

    # Should default to 60 days
    assert_includes result[:text], '60 days'
  end

  def test_log_command_rejects_days_over_365
    # Create user with no entries
    TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Test with days over 365
    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => '500'
    }

    result_json = suppress_logging do
      TimelogBot::Handlers::SlashCommandHandler.handle(params)
    end
    result = Oj.load(result_json, symbol_keys: true)

    # Should default to 60 days
    assert_includes result[:text], '60 days'
  end

  def test_log_command_handles_non_numeric_days
    # Create user with no entries
    TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Test with non-numeric input
    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => 'abc'
    }

    result_json = suppress_logging do
      TimelogBot::Handlers::SlashCommandHandler.handle(params)
    end
    result = Oj.load(result_json, symbol_keys: true)

    # Should default to 60 days (to_i on 'abc' returns 0, which is invalid)
    assert_includes result[:text], '60 days'
  end

  def test_log_command_includes_entry_id
    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U12345',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entry
    entry = TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today - 5,
      notes: 'Work with ID',
      logged_by_slack_id: 'U12345'
    )

    params = {
      'command' => '/log',
      'user_id' => 'U12345',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    # Check that the entry ID appears in the output (formatted with backticks)
    assert_includes result[:text], "`#{entry.id}`"
    assert_includes result[:text], 'Work with ID'
  end
end
