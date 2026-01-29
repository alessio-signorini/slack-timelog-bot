# frozen_string_literal: true

require_relative '../test_helper'

class BotFilteringTest < Minitest::Test
  def setup
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete
  end

  def test_bot_user_id_fetched_and_cached_on_first_call
    # Mock the Slack API auth.test call
    auth_response = OpenStruct.new(user_id: 'U_BOT_ID', user: 'timebot')
    TimelogBot::Services::SlackClient.client.stubs(:auth_test).returns(auth_response)

    # Reset class variable cache
    TimelogBot::Services::SlackClient.instance_variable_set(:@bot_user_id, nil)

    # First call - should hit API and store in DB
    bot_id = TimelogBot::Services::SlackClient.bot_user_id
    assert_equal 'U_BOT_ID', bot_id

    # Verify it was stored in the database
    bot_user = DB[:users].where(slack_user_id: 'U_BOT_ID').first
    assert bot_user, 'Bot user should be in database'
    assert_equal true, bot_user[:is_bot]
    assert_equal 'timebot', bot_user[:slack_username]
  end

  def test_bot_user_id_loaded_from_database_on_subsequent_boots
    # Insert bot user directly into DB (simulating previous boot)
    DB[:users].insert(
      slack_user_id: 'U_BOT_FROM_DB',
      slack_username: 'timebot',
      is_bot: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    # Reset class variable cache (simulating app restart)
    TimelogBot::Services::SlackClient.instance_variable_set(:@bot_user_id, nil)

    # Mock should NOT be called since we load from DB
    TimelogBot::Services::SlackClient.client.expects(:auth_test).never

    # Should load from database
    bot_id = TimelogBot::Services::SlackClient.bot_user_id
    assert_equal 'U_BOT_FROM_DB', bot_id
  end

  def test_bot_user_id_cached_in_class_variable
    # Insert bot user in DB
    DB[:users].insert(
      slack_user_id: 'U_BOT_CACHED',
      slack_username: 'timebot',
      is_bot: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    # Reset cache
    TimelogBot::Services::SlackClient.instance_variable_set(:@bot_user_id, nil)

    # First call loads from DB
    first_call = TimelogBot::Services::SlackClient.bot_user_id
    assert_equal 'U_BOT_CACHED', first_call

    # Second call should use cached value (verify by checking it returns same object reference)
    second_call = TimelogBot::Services::SlackClient.bot_user_id
    assert_equal first_call, second_call
  end

  def test_bot_mentions_filtered_from_parsed_entries
    # Setup: Create bot user in DB
    DB[:users].insert(
      slack_user_id: 'U_BOT_123',
      slack_username: 'timebot',
      is_bot: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    # Reset cache and set bot ID
    TimelogBot::Services::SlackClient.instance_variable_set(:@bot_user_id, 'U_BOT_123')

    # Mock LLM to return entries including the bot
    llm_response = {
      entries: [
        { user_id: 'U_BOT_123', minutes: 60, project: 'TestProject', project_confidence: 100, date: '2026-01-29', notes: 'Bot work' },
        { user_id: 'U_HUMAN_456', minutes: 60, project: 'TestProject', project_confidence: 100, date: '2026-01-29', notes: 'Human work' }
      ],
      needs_clarification: false,
      suggested_project_name: 'TestProject',
      unknown_user_mentions: []
    }

    # Mock LLM provider
    llm = mock('llm_provider')
    llm.stubs(:build_system_prompt).returns('system prompt')
    llm.stubs(:complete).returns(Oj.dump(llm_response, mode: :compat))
    TimelogBot::Services::LLMProvider.stubs(:for).returns(llm)

    # Mock user validation (only human is valid)
    human_user_info = OpenStruct.new(deleted: false, is_bot: false, profile: OpenStruct.new(display_name: 'Human'))
    TimelogBot::Services::SlackClient.stubs(:get_user_info).with('U_HUMAN_456').returns(human_user_info)

    # Parse message
    result = TimelogBot::Services::MessageParser.parse(
      text: '@timebot @user worked 1 hour on TestProject',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U_HUMAN_456'
    )

    # Bot should be filtered out, only human entry remains
    assert_equal 1, result[:entries].length
    assert_equal 'U_HUMAN_456', result[:entries][0][:user_id]
    refute_includes result[:entries].map { |e| e[:user_id] }, 'U_BOT_123'
  end

  def test_valid_slack_user_rejects_bots
    # Mock bot user from Slack API
    bot_user_info = OpenStruct.new(
      deleted: false,
      is_bot: true,
      name: 'testbot',
      profile: OpenStruct.new(display_name: 'Test Bot')
    )
    TimelogBot::Services::SlackClient.stubs(:get_user_info).with('U_BOT_NEW').returns(bot_user_info)

    # Should return false for bot
    is_valid = TimelogBot::Services::UserService.valid_slack_user?('U_BOT_NEW')
    assert_equal false, is_valid

    # Verify bot was stored in database
    bot_in_db = DB[:users].where(slack_user_id: 'U_BOT_NEW').first
    assert bot_in_db, 'Bot should be stored in database'
    assert_equal true, bot_in_db[:is_bot]
  end

  def test_valid_slack_user_checks_database_first_for_known_bots
    # Insert known bot in DB
    DB[:users].insert(
      slack_user_id: 'U_KNOWN_BOT',
      slack_username: 'knownbot',
      is_bot: true,
      created_at: Time.now,
      updated_at: Time.now
    )

    # Slack API should NOT be called since we know it's a bot from DB
    TimelogBot::Services::SlackClient.expects(:get_user_info).never

    # Should return false immediately
    is_valid = TimelogBot::Services::UserService.valid_slack_user?('U_KNOWN_BOT')
    assert_equal false, is_valid
  end

  def test_find_or_create_stores_bot_flag_from_slack
    # Mock bot user from Slack API
    bot_user_info = OpenStruct.new(
      deleted: false,
      is_bot: true,
      name: 'newbot',
      tz: 'America/New_York',
      profile: OpenStruct.new(display_name: 'New Bot')
    )
    TimelogBot::Services::SlackClient.stubs(:get_user_info).with('U_NEW_BOT').returns(bot_user_info)

    # Create user
    user = TimelogBot::Services::UserService.find_or_create('U_NEW_BOT')

    # Verify is_bot flag was set
    assert_equal true, user.is_bot
    assert_equal 'New Bot', user.slack_username
  end

  def test_find_or_create_stores_human_flag_from_slack
    # Mock human user from Slack API
    human_user_info = OpenStruct.new(
      deleted: false,
      is_bot: false,
      name: 'john',
      tz: 'America/Los_Angeles',
      profile: OpenStruct.new(display_name: 'John Doe')
    )
    TimelogBot::Services::SlackClient.stubs(:get_user_info).with('U_HUMAN_NEW').returns(human_user_info)

    # Create user
    user = TimelogBot::Services::UserService.find_or_create('U_HUMAN_NEW')

    # Verify is_bot flag is false
    assert_equal false, user.is_bot
    assert_equal 'John Doe', user.slack_username
  end

  def test_bot_filtering_in_message_validation
    # Setup bot in database
    DB[:users].insert(
      slack_user_id: 'U_BOT_VALIDATE',
      slack_username: 'timebot',
      is_bot: true,
      created_at: Time.now,
      updated_at: Time.now
    )
    TimelogBot::Services::SlackClient.instance_variable_set(:@bot_user_id, 'U_BOT_VALIDATE')

    # Mock LLM to return bot + invalid user
    llm_response = {
      entries: [
        { user_id: 'U_BOT_VALIDATE', minutes: 60, project: 'Test', project_confidence: 100, date: '2026-01-29', notes: 'Work' },
        { user_id: 'U_INVALID_USER', minutes: 60, project: 'Test', project_confidence: 100, date: '2026-01-29', notes: 'Work' }
      ],
      needs_clarification: false,
      suggested_project_name: 'Test',
      unknown_user_mentions: []
    }

    llm = mock('llm_provider')
    llm.stubs(:build_system_prompt).returns('system prompt')
    llm.stubs(:complete).returns(Oj.dump(llm_response, mode: :compat))
    TimelogBot::Services::LLMProvider.stubs(:for).returns(llm)

    # Mock invalid user (returns nil)
    TimelogBot::Services::SlackClient.stubs(:get_user_info).with('U_INVALID_USER').returns(nil)

    # Parse
    result = TimelogBot::Services::MessageParser.parse(
      text: '@timebot @invaliduser worked 1 hour on Test',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U_REQUESTER'
    )

    # Should report unknown user but NOT report the bot
    assert result[:unknown_users], 'Should have unknown users'
    assert_includes result[:unknown_users], 'U_INVALID_USER'
    refute_includes result[:unknown_users], 'U_BOT_VALIDATE', 'Bot should not be in unknown users'
  end
end
