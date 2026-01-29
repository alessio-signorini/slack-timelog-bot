# frozen_string_literal: true

require_relative '../test_helper'
require 'rack/test'

class SlackApiTest < Minitest::Test
  include Rack::Test::Methods
  include TimelogBot::TestHelpers

  def app
    TimelogBot::App
  end

  def setup
    setup_test_db
    stub_slack_api
    ENV['SLACK_SIGNING_SECRET'] = 'test_secret'
  end

  # Health check tests

  def test_health_endpoint_returns_ok
    get '/health'
    
    assert_equal 200, last_response.status
    
    body = Oj.load(last_response.body)
    assert_equal 'ok', body['status']
    assert body['timestamp']
  end

  # URL verification tests

  def test_events_endpoint_handles_url_verification
    challenge = 'test_challenge_12345'
    payload = { type: 'url_verification', challenge: challenge }
    
    body = payload.to_json
    headers = mock_slack_request(body)
    
    post '/slack/events', body, headers.merge('CONTENT_TYPE' => 'application/json')
    
    assert_equal 200, last_response.status
    assert_equal challenge, last_response.body
  end

  # Signature verification tests

  def test_events_endpoint_rejects_invalid_signature
    payload = { type: 'event_callback', event: {} }.to_json
    
    suppress_logging do
      post '/slack/events', payload, {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_X_SLACK_REQUEST_TIMESTAMP' => Time.now.to_i.to_s,
        'HTTP_X_SLACK_SIGNATURE' => 'v0=invalid_signature'
      }
    end
    
    assert_equal 401, last_response.status
    
    body = Oj.load(last_response.body)
    assert_equal 'Unauthorized', body['error']
  end

  def test_events_endpoint_rejects_expired_timestamp
    payload = { type: 'event_callback', event: {} }.to_json
    old_timestamp = (Time.now.to_i - 600).to_s # 10 minutes ago
    
    sig_basestring = "v0:#{old_timestamp}:#{payload}"
    signature = 'v0=' + OpenSSL::HMAC.hexdigest('SHA256', 'test_secret', sig_basestring)
    
    suppress_logging do
      post '/slack/events', payload, {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_X_SLACK_REQUEST_TIMESTAMP' => old_timestamp,
        'HTTP_X_SLACK_SIGNATURE' => signature
      }
    end
    
    assert_equal 401, last_response.status
  end

  def test_events_endpoint_accepts_valid_signature
    payload = { type: 'event_callback', event: { type: 'unknown' } }.to_json
    headers = mock_slack_request(payload)
    
    # Mock the event handler to do nothing
    TimelogBot::Handlers::EventHandler.stubs(:handle)
    
    post '/slack/events', payload, headers.merge('CONTENT_TYPE' => 'application/json')
    
    assert_equal 200, last_response.status
  end

  # Event callback tests

  def test_events_endpoint_acknowledges_event_callback
    payload = {
      type: 'event_callback',
      event: {
        type: 'app_mention',
        user: 'U12345678',
        text: 'test message',
        channel: 'C12345678',
        ts: '1234567890.123456'
      }
    }.to_json
    
    headers = mock_slack_request(payload)
    
    # Mock dependencies
    TimelogBot::Handlers::EventHandler.stubs(:handle)
    
    post '/slack/events', payload, headers.merge('CONTENT_TYPE' => 'application/json')
    
    assert_equal 200, last_response.status
    
    body = Oj.load(last_response.body)
    assert body['ok']
  end

  # Interactive endpoint tests

  def test_interactive_endpoint_rejects_missing_payload
    body = ''
    headers = mock_slack_request(body)
    
    post '/slack/interactive', body, headers.merge('CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    
    assert_equal 400, last_response.status
  end

  def test_interactive_endpoint_handles_block_actions
    payload = {
      type: 'block_actions',
      user: { id: 'U12345678' },
      channel: { id: 'C12345678' },
      actions: [
        { action_id: 'select_project', selected_option: { value: 'Mushroom' } }
      ]
    }
    
    body = "payload=#{CGI.escape(payload.to_json)}"
    headers = mock_slack_request(body)
    
    TimelogBot::Handlers::InteractiveHandler.stubs(:handle).returns(nil)
    
    post '/slack/interactive', body, headers.merge('CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    
    assert_equal 200, last_response.status
  end

  # Slash command tests

  def test_commands_endpoint_handles_report
    body = 'command=/report&user_id=U12345678&channel_id=C12345678&text='
    headers = mock_slack_request(body)
    
    TimelogBot::Handlers::SlashCommandHandler.stubs(:handle).returns({ text: 'No entries' }.to_json)
    
    post '/slack/commands', body, headers.merge('CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    
    assert_equal 200, last_response.status
  end

  def test_commands_endpoint_handles_team_report
    ENV['REPORT_ADMINS'] = 'U12345678'
    
    body = 'command=/team_report&user_id=U12345678&channel_id=C12345678&text=2026-01'
    headers = mock_slack_request(body)
    
    TimelogBot::Handlers::SlashCommandHandler.stubs(:handle).returns('')
    
    post '/slack/commands', body, headers.merge('CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    
    assert_equal 200, last_response.status
  end

  # Error handling tests

  def test_returns_404_for_unknown_routes
    get '/unknown/path'
    
    assert_equal 404, last_response.status
    
    body = Oj.load(last_response.body)
    assert_equal 'Not found', body['error']
  end

  # Event handler integration tests

  def test_time_log_event_stores_original_message
    user = create_test_user(slack_id: 'U12345678')
    project = create_test_project(name: 'Mushroom')
    
    original_message = '<@U07MK9CFZHJ> I spent 3 hours on Mushroom today working on data analysis'
    
    # Mock the message parser
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
    
    payload = {
      type: 'event_callback',
      event_id: 'Ev01234567890',
      event: {
        type: 'app_mention',
        user: 'U12345678',
        text: original_message,
        channel: 'C12345678',
        ts: '1234567890.123456'
      }
    }.to_json
    
    headers = mock_slack_request(payload)
    
    post '/slack/events', payload, headers.merge('CONTENT_TYPE' => 'application/json')
    
    assert_equal 200, last_response.status
    
    # Verify the time entry was created with original_message in event_log
    entry = TimelogBot::Models::TimeEntry.last
    assert entry, 'Time entry should be created'
    assert entry.event_log_id, 'Time entry should have event_log_id'
    
    # Check original message in event log
    event_log = DB[:event_logs].where(id: entry.event_log_id).first
    assert event_log, 'Event log should exist'
    assert_equal original_message, event_log[:original_message]
    
    assert_equal 180, entry.minutes
    assert_equal project.id, entry.project_id
  end

  def test_event_handler_passes_requesting_user_id_to_parser
    user = create_test_user(slack_id: 'U12345678')
    
    original_message = '<@U07MK9CFZHJ> I worked 2 hours on Monkey yesterday'
    
    # Capture the arguments passed to MessageParser.parse
    captured_args = nil
    TimelogBot::Services::MessageParser.stubs(:parse).with do |args|
      captured_args = args
      true
    end.returns({ entries: [] })
    
    payload = {
      type: 'event_callback',
      event: {
        type: 'app_mention',
        user: 'U12345678',
        text: original_message,
        channel: 'C12345678',
        ts: '1234567890.123456'
      }
    }.to_json
    
    headers = mock_slack_request(payload)
    
    post '/slack/events', payload, headers.merge('CONTENT_TYPE' => 'application/json')
    
    assert_equal 200, last_response.status
    
    # Verify requesting_user_id was passed
    assert captured_args, 'MessageParser.parse should be called'
    assert_equal 'U12345678', captured_args[:requesting_user_id]
    assert_equal original_message, captured_args[:text]
  end
end
