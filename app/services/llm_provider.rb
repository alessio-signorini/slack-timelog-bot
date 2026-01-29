# frozen_string_literal: true

module TimelogBot
  module Services
    # Base class for LLM providers
    # Subclasses must implement #complete(prompt) method
    class LLMProvider
      class << self
        def for(model_string)
          provider, model = parse_model_string(model_string)
          
          case provider
          when 'anthropic'
            AnthropicClient.new(model: model)
          else
            raise UnsupportedProviderError, "Unknown LLM provider: #{provider}"
          end
        end

        private

        def parse_model_string(model_string)
          parts = model_string.to_s.split('/', 2)
          
          if parts.length != 2
            raise InvalidModelStringError, 
              "LLM_MODEL must be in format 'provider/model' (e.g., 'anthropic/claude-haiku-4.5')"
          end

          parts
        end
      end

      def complete(prompt)
        raise NotImplementedError, "Subclasses must implement #complete"
      end

      def prompt_template
        raise NotImplementedError, "Subclasses must implement #prompt_template"
      end

      class UnsupportedProviderError < StandardError; end
      class InvalidModelStringError < StandardError; end
      class APIError < StandardError; end
    end
  end
end
