require_relative '../test_helper'

class AsyncSlashCommandTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    # Clean database
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete

    # Create test user
    @user = TimelogBot::Models::User.create(
      slack_user_id: 'U123',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )

    # Create test project
    @project = TimelogBot::Models::Project.create(name: 'TestProject')

    # Create test entry
    TimelogBot::Models::TimeEntry.create(
      user_id: @user.id,
      project_id: @project.id,
      minutes: 180,
      date: Date.today - 10,
      notes: 'Test work',
      logged_by_slack_id: @user.slack_user_id
    )
  end

  def teardown
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete
  end

  def test_log_command_returns_immediate_acknowledgment_with_response_url
    # Stub the async response
    response_posted = false
    TimelogBot::Services::SlackClient.stubs(:post_to_response_url).with do |url, payload|
      response_posted = true
      true
    end.returns(true)

    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/log',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => '',
        'response_url' => 'https://hooks.slack.com/commands/1234/5678'
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_equal '⏳ Processing your request...', response[:text]
    end

    # Give thread a moment to complete
    sleep 0.2

    # Verify the async method was called
    assert response_posted, "Expected post_to_response_url to be called"
  end

  def test_log_command_processes_synchronously_without_response_url
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/log',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => ''
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_includes response[:text], 'Your Time Entries (Last 60 Days)'
      assert_includes response[:text], 'TestProject'
    end
  end

  def test_team_log_command_returns_immediate_acknowledgment_with_response_url
    ENV['REPORT_ADMINS'] = @user.slack_user_id

    # Stub the async response
    response_posted = false
    TimelogBot::Services::SlackClient.stubs(:post_to_response_url).with do |url, payload|
      response_posted = true
      true
    end.returns(true)

    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/team_log',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => '',
        'response_url' => 'https://hooks.slack.com/commands/1234/5678'
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_equal '⏳ Processing your request...', response[:text]
    end

    # Give thread a moment to complete
    sleep 0.2

    # Verify the async method was called
    assert response_posted, "Expected post_to_response_url to be called"

    ENV.delete('REPORT_ADMINS')
  end

  def test_team_log_command_processes_synchronously_without_response_url
    ENV['REPORT_ADMINS'] = @user.slack_user_id

    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/team_log',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => ''
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_includes response[:text], 'Team Time Entries (Last 60 Days)'
      assert_includes response[:text], 'TestProject'
    end

    ENV.delete('REPORT_ADMINS')
  end
end
