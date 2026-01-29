# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['LOG_LEVEL'] = 'WARN'  # Suppress DEBUG logs during tests
ENV['ANTHROPIC_API_KEY'] ||= 'test-api-key-for-testing'
ENV['SLACK_SIGNING_SECRET'] = 'test_secret'  # Must match mock_slack_request default
ENV['SLACK_BOT_TOKEN'] ||= 'xoxb-test-token'
ENV['LLM_MODEL'] ||= 'anthropic/claude-haiku-4.5'

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'
require 'mocha/minitest'
require 'fileutils'
require 'sequel'

# Set up test database path
test_db_path = File.join(__dir__, '..', 'tmp', 'test.db')
FileUtils.mkdir_p(File.dirname(test_db_path))

# Clean up test database before tests
FileUtils.rm_f(test_db_path)

# Connect to DB and run migrations BEFORE loading models
DB = Sequel.connect("sqlite://#{test_db_path}")
DB.loggers << Logger.new($stdout, level: :warn)

require 'sequel/extensions/migration'
Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))

# Now load environment (which will use existing DB constant)
require_relative '../config/environment'

# Load the app
require_relative '../app'

module TimelogBot
  module TestHelpers
    def setup_test_db
      # Clear tables before each test
      DB[:time_entries].delete
      DB[:event_logs].delete
      DB[:projects].delete
      DB[:users].delete
    end

    def create_test_user(slack_id: 'U12345678', username: 'testuser', timezone: 'America/Los_Angeles')
      Models::User.create(
        slack_user_id: slack_id,
        slack_username: username,
        timezone: timezone
      )
    end

    def create_test_project(name: 'Test Project')
      Models::Project.create(name: name)
    end

    def create_test_time_entry(user:, project:, minutes: 60, date: Date.today, notes: nil)
      Models::TimeEntry.create(
        user_id: user.id,
        project_id: project.id,
        minutes: minutes,
        date: date,
        notes: notes,
        logged_by_slack_id: user.slack_user_id
      )
    end

    def mock_slack_request(body, signing_secret: 'test_secret')
      timestamp = Time.now.to_i.to_s
      sig_basestring = "v0:#{timestamp}:#{body}"
      signature = 'v0=' + OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)

      {
        'HTTP_X_SLACK_REQUEST_TIMESTAMP' => timestamp,
        'HTTP_X_SLACK_SIGNATURE' => signature,
        'rack.input' => StringIO.new(body)  # Ensure body is available as raw input
      }
    end

    def stub_slack_api
      WebMock.stub_request(:any, /slack.com/).to_return(status: 200, body: '{"ok":true}')
    end

    def stub_anthropic_api(response_json)
      WebMock.stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            content: [{ type: 'text', text: response_json.to_json }]
          }.to_json
        )
    end

    # Suppress log output for tests that intentionally trigger warnings/errors
    def suppress_logging
      original_logger = $logger
      original_db_loggers = DB.loggers.dup
      $logger = Logger.new(File.open(File::NULL, 'w'))
      DB.loggers.clear
      yield
    ensure
      $logger = original_logger
      DB.loggers.replace(original_db_loggers)
    end
  end
end
