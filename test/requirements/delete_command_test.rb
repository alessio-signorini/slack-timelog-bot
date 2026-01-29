require_relative '../test_helper'

class DeleteCommandTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    # Clean database
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete

    # Set admin user
    ENV['REPORT_ADMINS'] = 'U09JSSAACB1'

    # Create test users
    @user = TimelogBot::Models::User.create(
      slack_user_id: 'U123',
      slack_username: 'alice',
      timezone: 'America/Los_Angeles'
    )
    
    @other_user = TimelogBot::Models::User.create(
      slack_user_id: 'U456',
      slack_username: 'bob',
      timezone: 'America/Los_Angeles'
    )
    
    @admin_user = TimelogBot::Models::User.create(
      slack_user_id: 'U09JSSAACB1',
      slack_username: 'admin',
      timezone: 'America/Los_Angeles'
    )

    # Create test project
    @project = TimelogBot::Models::Project.create(name: 'Mushroom')

    # Create test entries
    @user_entry = TimelogBot::Models::TimeEntry.create(
      user_id: @user.id,
      project_id: @project.id,
      minutes: 180,
      date: Date.today - 1,
      notes: 'User entry',
      logged_by_slack_id: @user.slack_user_id
    )

    @other_entry = TimelogBot::Models::TimeEntry.create(
      user_id: @other_user.id,
      project_id: @project.id,
      minutes: 120,
      date: Date.today,
      notes: 'Other user entry',
      logged_by_slack_id: @other_user.slack_user_id
    )
  end

  def teardown
    ENV.delete('REPORT_ADMINS')
    DB[:time_entries].delete
    DB[:users].delete
    DB[:projects].delete
  end

  def test_requires_entry_id
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => ''
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_match(/Please provide an entry ID/, response[:text])
      assert_match(/Usage: `\/delete \[ID\]`/, response[:text])
      assert_match(/You can find entry IDs using `\/log`/, response[:text])
    end
  end

  def test_rejects_invalid_entry_id
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => 'abc'
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_match(/Invalid entry ID: abc/, response[:text])
    end
  end

  def test_user_can_delete_own_entry
    entry_id = @user_entry.id
    
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => entry_id.to_s
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_match(/✅ Deleted entry ##{entry_id}/, response[:text])
      assert_match(/Mushroom/, response[:text])
      assert_match(/3\.0h/, response[:text])
      
      # Verify entry was deleted
      assert_nil TimelogBot::Models::TimeEntry[entry_id]
    end
  end

  def test_user_cannot_delete_other_users_entry
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => @other_entry.id.to_s
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_match(/You don't have permission/, response[:text])
      assert_match(/You can only delete your own entries/, response[:text])
      
      # Verify entry was NOT deleted
      refute_nil TimelogBot::Models::TimeEntry[@other_entry.id]
    end
  end

  def test_admin_can_delete_any_entry
    entry_id = @other_entry.id
    
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @admin_user.slack_user_id,
        'channel_id' => 'C123',
        'text' => entry_id.to_s
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_match(/✅ Deleted entry ##{entry_id}/, response[:text])
      
      # Verify entry was deleted
      assert_nil TimelogBot::Models::TimeEntry[entry_id]
    end
  end

  def test_handles_nonexistent_entry_id
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => '99999'
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_equal 'ephemeral', response[:response_type]
      assert_match(/Entry #99999 not found/, response[:text])
    end
  end

  def test_shows_entry_details_in_confirmation
    entry_id = @user_entry.id
    
    suppress_logging do
      result_json = TimelogBot::Handlers::SlashCommandHandler.handle({
        'command' => '/delete',
        'user_id' => @user.slack_user_id,
        'channel_id' => 'C123',
        'text' => entry_id.to_s
      })

      response = Oj.load(result_json, symbol_keys: true)
      assert_match(/@alice/, response[:text])
      assert_match(/Mushroom/, response[:text])
      assert_match(/3\.0h/, response[:text])
      assert_match(/User entry/, response[:text])
      assert_match(/#{Date.today - 1}/, response[:text])
    end
  end
end
