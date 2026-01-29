# frozen_string_literal: true

require_relative '../test_helper'

class LLMIntegrationTest < Minitest::Test
  include TimelogBot::TestHelpers

  def setup
    setup_test_db
    ENV['LLM_MODEL'] = 'anthropic/claude-haiku-4.5'
    ENV['ANTHROPIC_API_KEY'] = 'test-api-key'
    
    # Create test projects for prompts
    create_test_project(name: 'Mushroom')
    create_test_project(name: 'Monkey')
    create_test_project(name: 'Barometer')
  end

  def test_provider_factory_parses_model_string
    provider = TimelogBot::Services::LLMProvider.for('anthropic/claude-haiku-4.5')
    
    assert_instance_of TimelogBot::Services::AnthropicClient, provider
  end

  def test_provider_factory_raises_for_invalid_format
    assert_raises TimelogBot::Services::LLMProvider::InvalidModelStringError do
      TimelogBot::Services::LLMProvider.for('invalid-format')
    end
  end

  def test_provider_factory_raises_for_unknown_provider
    assert_raises TimelogBot::Services::LLMProvider::UnsupportedProviderError do
      TimelogBot::Services::LLMProvider.for('unknown/model')
    end
  end

  def test_anthropic_client_loads_haiku_prompt
    client = TimelogBot::Services::AnthropicClient.new(model: 'claude-haiku-4.5')
    
    prompt = client.prompt_template
    
    assert prompt.include?('time tracking assistant')
    assert prompt.include?('{{current_datetime}}')
    assert prompt.include?('{{project_list}}')
  end

  def test_anthropic_client_loads_sonnet_prompt
    client = TimelogBot::Services::AnthropicClient.new(model: 'claude-sonnet-4.5')
    
    prompt = client.prompt_template
    
    assert prompt.include?('expert time tracking assistant')
  end

  def test_anthropic_client_builds_system_prompt_with_context
    client = TimelogBot::Services::AnthropicClient.new(model: 'claude-haiku-4.5')
    
    prompt = client.build_system_prompt(
      current_datetime: '2026-01-27 10:30:00 PST',
      user_timezone: 'America/Los_Angeles',
      requesting_user_id: 'U12345678',
      project_list: 'Monkey, Barometer, Mushroom'
    )
    
    assert prompt.include?('2026-01-27 10:30:00 PST')
    assert prompt.include?('America/Los_Angeles')
    assert prompt.include?('U12345678')
    assert prompt.include?('Monkey, Barometer, Mushroom')
    
    # Should not have unsubstituted placeholders
    refute prompt.include?('{{current_datetime}}')
    refute prompt.include?('{{requesting_user_id}}')
    refute prompt.include?('{{project_list}}')
  end

  def test_message_parser_returns_error_on_llm_failure
    TimelogBot::Services::LLMProvider.stubs(:for).raises(
      TimelogBot::Services::LLMProvider::APIError.new('Service unavailable')
    )
    
    result = suppress_logging do
      TimelogBot::Services::MessageParser.parse(
        text: 'test message',
        user_timezone: 'America/Los_Angeles',
        requesting_user_id: 'U12345678'
      )
    end
    
    assert result[:error]
    assert result[:error].include?('trouble')
  end

  def test_anthropic_prompts_use_xml_structure
    haiku_client = TimelogBot::Services::AnthropicClient.new(model: 'claude-haiku-4.5')
    sonnet_client = TimelogBot::Services::AnthropicClient.new(model: 'claude-sonnet-4.5')
    
    haiku_prompt = haiku_client.prompt_template
    sonnet_prompt = sonnet_client.prompt_template
    
    # Check for XML tags in both prompts
    [haiku_prompt, sonnet_prompt].each do |prompt|
      assert prompt.include?('<context>'), 'Prompt should have <context> tag'
      assert prompt.include?('</context>'), 'Prompt should have </context> tag'
      assert prompt.include?('<task>'), 'Prompt should have <task> tag'
      assert prompt.include?('<rules>'), 'Prompt should have <rules> tag'
      assert prompt.include?('<output_format>'), 'Prompt should have <output_format> tag'
      assert prompt.include?('<examples>'), 'Prompt should have <examples> tag'
      assert prompt.include?('<example>'), 'Prompt should have <example> tag'
    end
  end

  def test_prompts_include_requesting_user_id_in_context
    haiku_client = TimelogBot::Services::AnthropicClient.new(model: 'claude-haiku-4.5')
    sonnet_client = TimelogBot::Services::AnthropicClient.new(model: 'claude-sonnet-4.5')
    
    haiku_prompt = haiku_client.prompt_template
    sonnet_prompt = sonnet_client.prompt_template
    
    # Check both prompts have requesting_user_id placeholder in context
    [haiku_prompt, sonnet_prompt].each do |prompt|
      assert prompt.include?('{{requesting_user_id}}'), 'Prompt should have requesting_user_id placeholder'
      assert prompt.include?('<requesting_user_id>'), 'Prompt should have requesting_user_id XML tag'
    end
  end
end
