# frozen_string_literal: true

require 'anthropic'

module TimelogBot
  module Services
    class AnthropicClient < LLMProvider
      MAX_RETRIES = 3
      RETRY_DELAY = 1 # seconds
      TIMEOUT = 30 # seconds

      def initialize(model:)
        @model_id = model
        
        # Load the appropriate prompt template
        @prompt_template = load_prompt_template(model)
      end

      def client
        @client ||= Anthropic::Client.new(
          access_token: ENV.fetch('ANTHROPIC_API_KEY')
        )
      end

      def complete(system_context:, user_message:)
        retries = 0
        
        begin
          response = client.messages(
            parameters: {
              model: @model_id,
              max_tokens: 1024,
              system: system_context,
              messages: [
                { role: 'user', content: user_message }
              ]
            }
          )

          extract_content(response)
        rescue Anthropic::Error => e
          # Check if it's a rate limit error (status 429)
          if e.message.include?('429') || e.message.downcase.include?('rate limit')
            retries += 1
            if retries <= MAX_RETRIES
              $logger.warn("Rate limited, retrying in #{RETRY_DELAY * retries}s...")
              sleep(RETRY_DELAY * retries)
              retry
            end
            raise APIError, "Rate limit exceeded after #{MAX_RETRIES} retries"
          end
          
          # Otherwise treat as general API error
          $logger.error("Anthropic API error: #{e.message}")
          raise APIError, "LLM service error: #{e.message}"
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
          retries += 1
          if retries <= MAX_RETRIES
            $logger.warn("Connection error, retrying in #{RETRY_DELAY}s...")
            sleep(RETRY_DELAY)
            retry
          end
          raise APIError, "Could not connect to Anthropic API: #{e.message}"
        rescue StandardError => e
          $logger.error("Unexpected error calling Anthropic: #{e.class} - #{e.message}")
          raise APIError, "Unexpected error: #{e.message}"
        end
      end

      def prompt_template
        @prompt_template
      end

      def build_system_prompt(current_datetime:, user_timezone:, requesting_user_id:, project_list:)
        @prompt_template
          .gsub('{{current_datetime}}', current_datetime)
          .gsub('{{user_timezone}}', user_timezone)
          .gsub('{{requesting_user_id}}', requesting_user_id)
          .gsub('{{project_list}}', project_list)
      end

      private

      def load_prompt_template(model)
        # Determine which prompt file to use based on model
        prompt_file = if model.include?('haiku')
          'anthropic_haiku.txt'
        elsif model.include?('sonnet')
          'anthropic_sonnet.txt'
        else
          'anthropic_haiku.txt' # default
        end

        prompt_path = File.join(__dir__, '..', '..', 'prompts', prompt_file)
        
        unless File.exist?(prompt_path)
          raise "Prompt template not found: #{prompt_path}"
        end

        File.read(prompt_path)
      end

      def extract_content(response)
        content = response['content']
        return nil if content.nil? || content.empty?

        # Get text content from response
        text_block = content.find { |c| c['type'] == 'text' }
        text_block&.dig('text')
      end
    end
  end
end
