# frozen_string_literal: true

require_relative '../test_helper'

class TeamLogCommandTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete
    ENV['REPORT_ADMINS'] = 'U_ADMIN'
  end

  def test_team_log_command_requires_admin
    # Create non-admin user
    TimelogBot::Models::User.create(
      slack_user_id: 'U_REGULAR',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    params = {
      'command' => '/team_log',
      'user_id' => 'U_REGULAR',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_equal 'ephemeral', result[:response_type]
    assert_includes result[:text], "don't have permission"
  end

  def test_team_log_command_returns_all_users_entries
    # Create admin
    admin = TimelogBot::Models::User.create(
      slack_user_id: 'U_ADMIN',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    # Create regular users
    user1 = TimelogBot::Models::User.create(
      slack_user_id: 'U_USER1',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    user2 = TimelogBot::Models::User.create(
      slack_user_id: 'U_USER2',
      slack_username: 'bob',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entries for different users
    TimelogBot::Models::TimeEntry.create(
      user_id: user1.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today - 5,
      notes: 'Alice work',
      logged_by_slack_id: 'U_USER1'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user2.id,
      project_id: project.id,
      minutes: 180,
      date: Date.today - 3,
      notes: 'Bob work',
      logged_by_slack_id: 'U_USER2'
    )

    params = {
      'command' => '/team_log',
      'user_id' => 'U_ADMIN',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_equal 'ephemeral', result[:response_type]
    assert_includes result[:text], 'Team Time Entries (Last 60 Days)'
    assert_includes result[:text], '@alice'
    assert_includes result[:text], '@bob'
    assert_includes result[:text], 'Alice work'
    assert_includes result[:text], 'Bob work'
    assert_includes result[:text], '2.0h'
    assert_includes result[:text], '3.0h'
    assert_includes result[:text], 'Total:'
    assert_includes result[:text], '5.0h'
  end

  def test_team_log_command_accepts_custom_days
    # Create admin
    admin = TimelogBot::Models::User.create(
      slack_user_id: 'U_ADMIN',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U_USER1',
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
      logged_by_slack_id: 'U_USER1'
    )

    # Create entry outside 30 days but within 60
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 180,
      date: Date.today - 45,
      notes: 'Older work',
      logged_by_slack_id: 'U_USER1'
    )

    # Request only last 30 days
    params = {
      'command' => '/team_log',
      'user_id' => 'U_ADMIN',
      'channel_id' => 'C12345',
      'text' => '30'
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_includes result[:text], 'Team Time Entries (Last 30 Days)'
    assert_includes result[:text], 'Recent work'
    refute_includes result[:text], 'Older work'
  end

  def test_team_log_command_shows_entry_ids
    # Create admin
    admin = TimelogBot::Models::User.create(
      slack_user_id: 'U_ADMIN',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U_USER1',
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
      logged_by_slack_id: 'U_USER1'
    )

    params = {
      'command' => '/team_log',
      'user_id' => 'U_ADMIN',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    # Check that the entry ID appears in the output
    assert_includes result[:text], "`#{entry.id}`"
  end

  def test_team_log_command_shows_user_column
    # Create admin
    admin = TimelogBot::Models::User.create(
      slack_user_id: 'U_ADMIN',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U_USER1',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create project
    project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create entry logged by someone else
    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 120,
      date: Date.today - 5,
      notes: 'Work',
      logged_by_slack_id: 'U_ADMIN'
    )

    params = {
      'command' => '/team_log',
      'user_id' => 'U_ADMIN',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    # Should show user column
    assert_includes result[:text], '@alice'
    # Should show who logged it
    assert_includes result[:text], 'Logged by @admin'
  end

  def test_team_log_command_returns_message_when_no_entries
    # Create admin
    TimelogBot::Models::User.create(
      slack_user_id: 'U_ADMIN',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    params = {
      'command' => '/team_log',
      'user_id' => 'U_ADMIN',
      'channel_id' => 'C12345',
      'text' => ''
    }

    result_json = TimelogBot::Handlers::SlashCommandHandler.handle(params)
    result = Oj.load(result_json, symbol_keys: true)

    assert_equal 'ephemeral', result[:response_type]
    assert_includes result[:text], "No time entries found in the last 60 days"
  end

  def test_team_log_command_orders_entries_by_date
    # Create admin
    admin = TimelogBot::Models::User.create(
      slack_user_id: 'U_ADMIN',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    # Create user
    user = TimelogBot::Models::User.create(
      slack_user_id: 'U_USER1',
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
      logged_by_slack_id: 'U_USER1'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 60,
      date: Date.today - 20,
      notes: 'First',
      logged_by_slack_id: 'U_USER1'
    )

    TimelogBot::Models::TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: 60,
      date: Date.today - 15,
      notes: 'Second',
      logged_by_slack_id: 'U_USER1'
    )

    params = {
      'command' => '/team_log',
      'user_id' => 'U_ADMIN',
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
end
