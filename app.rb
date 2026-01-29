# frozen_string_literal: true

require 'sinatra/base'
require 'json'

module TimelogBot
  class App < Sinatra::Base
    configure do
      set :show_exceptions, false
      set :raise_errors, false
      set :dump_errors, false
    end

    before do
      content_type :json
      # Cache raw request body before Sinatra parses it for params
      # This is needed for Slack signature verification
      if request.body
        request.body.rewind
        @raw_request_body = request.body.read
        request.body.rewind
      else
        @raw_request_body = ''
      end
    end

    # Health check endpoint
    get '/health' do
      begin
        # Verify database connectivity
        DB.execute('SELECT 1')
        
        # Check disk space (for Fly.io volume)
        if ENV['RACK_ENV'] == 'production'
          stat = File.stat('/data')
          free_mb = `df -m /data | tail -1 | awk '{print $4}'`.to_i
          if free_mb < 100
            $logger.warn("Low disk space: #{free_mb}MB remaining")
          end
        end

        { status: 'ok', timestamp: Time.now.iso8601 }.to_json
      rescue StandardError => e
        status 503
        { status: 'error', message: e.message }.to_json
      end
    end

    # Slack Events API endpoint
    post '/slack/events' do
      # Verify request is from Slack
      unless verify_slack_request
        halt 401, { error: 'Unauthorized' }.to_json
      end

      body = request.body.read
      request.body.rewind
      event = parse_json(body)

      # Handle URL verification challenge
      if event['type'] == 'url_verification'
        content_type :text
        return event['challenge']
      end

      # Handle event callbacks
      if event['type'] == 'event_callback'
        # Use background processing in production, synchronous in test
        if ENV['RACK_ENV'] == 'test'
          Handlers::EventHandler.handle(event)
        else
          Thread.new do
            begin
              Handlers::EventHandler.handle(event)
            rescue StandardError => e
              $logger.error("Background event processing error: #{e.message}")
              $logger.error(e.backtrace.first(10).join("\n"))
            end
          end
        end
      end

      # Acknowledge receipt immediately
      status 200
      { ok: true }.to_json
    end

    # Slack Interactive Components endpoint
    post '/slack/interactive' do
      unless verify_slack_request
        halt 401, { error: 'Unauthorized' }.to_json
      end

      # Interactive payloads come as form-encoded with a 'payload' field
      payload_json = params['payload']
      unless payload_json
        halt 400, { error: 'Missing payload' }.to_json
      end

      payload = parse_json(payload_json)
      
      result = Handlers::InteractiveHandler.handle(payload)
      
      if result.is_a?(Hash)
        result.to_json
      else
        status 200
        ''
      end
    end

    # Slack Slash Commands endpoint
    post '/slack/commands' do
      unless verify_slack_request
        halt 401, { error: 'Unauthorized' }.to_json
      end

      Handlers::SlashCommandHandler.handle(params)
    end

    # Error handlers
    error do
      e = env['sinatra.error']
      $logger.error("Unhandled error: #{e.class} - #{e.message}")
      $logger.error(e.backtrace.first(10).join("\n"))
      
      status 500
      { error: 'Internal server error' }.to_json
    end

    not_found do
      { error: 'Not found' }.to_json
    end

    private

    def verify_slack_request
      verifier = Helpers::SlackVerifier.new
      verifier.verify(request, cached_body: @raw_request_body)
    end

    def parse_json(body)
      Oj.load(body, symbol_keys: false)
    rescue Oj::ParseError => e
      $logger.error("JSON parse error: #{e.message}")
      halt 400, { error: 'Invalid JSON' }.to_json
    end
  end
end
