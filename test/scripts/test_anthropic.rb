#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script to verify Anthropic API integration works
# Usage: ANTHROPIC_API_KEY=sk-ant-... ruby test_anthropic.rb

# Ensure we have the API key before loading anything
unless ENV['ANTHROPIC_API_KEY']
  require 'dotenv/load' rescue nil
end

unless ENV['ANTHROPIC_API_KEY']
  puts "❌ ERROR: ANTHROPIC_API_KEY not set"
  puts "Usage: ANTHROPIC_API_KEY=sk-ant-... ruby test_anthropic.rb"
  exit 1
end

require 'bundler/setup'
require_relative 'config/environment'

def test_message_parsing
  puts "Testing Anthropic API message parsing..."
  puts "=" * 60
  
  # Check API key
  unless ENV['ANTHROPIC_API_KEY']
    puts "❌ ERROR: ANTHROPIC_API_KEY not set"
    puts "Usage: ANTHROPIC_API_KEY=sk-ant-... ruby test_anthropic.rb"
    exit 1
  end
  
  # Warn about Slack token
  unless ENV['SLACK_BOT_TOKEN']
    puts "⚠️  WARNING: SLACK_BOT_TOKEN not set - user validation will fail"
    puts "   This is OK for testing message parsing"
    puts "=" * 60
  end
  
  # Test message
  test_message = "I spent 3 hours on Monkey today working on data analysis"
  test_user_id = "U09JSSAACB1"
  
  puts "Test message: #{test_message}"
  puts "User ID: #{test_user_id}"
  puts "-" * 60
  
  begin
    # Parse the message (class method, not instance)
    puts "Calling Anthropic API..."
    puts "This may take 10-30 seconds..."
    result = TimelogBot::Services::MessageParser.parse(
      text: test_message,
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: test_user_id
    )
    
    puts "\nReceived response from API!"
    puts "Raw result: #{result.inspect}"
    puts "-" * 60
    
    if result[:error]
      puts "\n❌ Parse Error: #{result[:error]}"
      exit 1
    end
    
    if result[:unknown_users]&.any?
      puts "\n⚠️  Unknown users found: #{result[:unknown_users].join(', ')}"
      puts "Note: This is expected in testing with fake user IDs"
    end
    
    if result[:clarification_needed]
      puts "\n⚠️  Clarification needed:"
      puts "Message: #{result[:clarification_needed]}"
      puts "Options: #{result[:project_options]&.join(', ')}"
    end
    
    if result[:entries]
      puts "\n✅ SUCCESS! Parsed entries:"
      puts "-" * 60
      result[:entries].each_with_index do |entry, i|
        puts "\nEntry #{i + 1}:"
        puts "  User: #{entry[:user_id]}"
        puts "  Project: #{entry[:project]}"
        puts "  Minutes: #{entry[:minutes]}"
        puts "  Hours: #{entry[:minutes] / 60.0}"
        puts "  Date: #{entry[:date]}"
        puts "  Notes: #{entry[:notes]}"
      end
      
      puts "\n✅ Anthropic API integration is working correctly!"
    end
    
  rescue TimelogBot::Services::LLMProvider::APIError => e
    puts "\n❌ API Error: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "\n❌ Unexpected Error: #{e.class} - #{e.message}"
    puts "\nBacktrace:"
    puts e.backtrace.first(10)
    exit 1
  end
end

# Run test
test_message_parsing
