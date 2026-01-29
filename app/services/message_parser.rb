# frozen_string_literal: true

require 'time'

module TimelogBot
  module Services
    class MessageParser
      CONFIDENCE_THRESHOLD = 70

      class << self
        def parse(text:, user_timezone:, requesting_user_id:, model: nil)
          $logger.debug("Parsing message: #{text}")

          # Get LLM provider
          llm_model = model || ENV.fetch('LLM_MODEL', 'anthropic/claude-haiku-4.5')
          llm = LLMProvider.for(llm_model)

          # Build context
          current_datetime = format_current_time(user_timezone)
          project_list = Models::Project.all_names.join(', ')

          system_prompt = llm.build_system_prompt(
            current_datetime: current_datetime,
            user_timezone: user_timezone,
            requesting_user_id: requesting_user_id,
            project_list: project_list
          )

          # Use the message as-is
          user_message = text

          # Call LLM
          response_text = llm.complete(
            system_context: system_prompt,
            user_message: user_message
          )
          
          $logger.debug("LLM response: #{response_text}")

          # Parse JSON response
          parsed = parse_llm_response(response_text)
          
          $logger.debug("Parsed entries: #{parsed[:entries].inspect}")
          
          if parsed[:error]
            return { error: parsed[:error] }
          end

          # Validate users
          unknown_users = validate_users(parsed[:entries], parsed[:unknown_user_mentions])
          if unknown_users.any?
            return { error: nil, unknown_users: unknown_users }
          end

          # Check if project clarification needed
          needs_clarification = parsed[:needs_clarification] || 
                                 parsed[:entries].any? { |e| (e[:project_confidence] || 0) < CONFIDENCE_THRESHOLD }

          if needs_clarification
            return {
              needs_project_selection: true,
              suggested_project: parsed[:suggested_project_name],
              parsed_data: {
                entries: parsed[:entries].map do |e|
                  {
                    'user_id' => e[:user_id],
                    'minutes' => e[:minutes],
                    'date' => e[:date],
                    'notes' => e[:notes]
                  }
                end,
                suggested_project_name: parsed[:suggested_project_name]
              }
            }
          end

          # All good - format entries for creation
          # Filter out bot's own user ID from mentions
          bot_id = SlackClient.bot_user_id
          entries = parsed[:entries]
            .reject { |e| e[:user_id] == bot_id }
            .map do |e|
              {
                user_id: e[:user_id],
                minutes: e[:minutes].to_i,
                project: e[:project],
                date: Date.parse(e[:date]),
                notes: e[:notes]
              }
            end

          $logger.debug("Parsed #{entries.length} entries: #{entries.inspect}")

          { entries: entries }

        rescue LLMProvider::APIError => e
          $logger.error("LLM error: #{e.message}")
          { error: "I'm having trouble understanding right now. Please try again in a moment. 🙏" }
        rescue StandardError => e
          $logger.error("Parse error: #{e.class} - #{e.message}")
          $logger.error(e.backtrace.first(5).join("\n"))
          { error: "Something went wrong parsing your message. Try rephrasing it?" }
        end

        private

        def format_current_time(timezone)
          # Try to use the timezone, fallback to UTC
          begin
            require 'tzinfo'
            tz = TZInfo::Timezone.get(timezone)
            tz.now.strftime('%Y-%m-%d %H:%M:%S %Z')
          rescue LoadError, TZInfo::InvalidTimezoneIdentifier
            Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')
          end
        end

        def parse_llm_response(text)
          return { error: 'Empty response from LLM' } if text.nil? || text.strip.empty?

          # Clean up potential markdown code blocks
          cleaned = text.strip
          cleaned = cleaned.gsub(/^```json\s*/, '').gsub(/^```\s*/, '').gsub(/\s*```$/, '')

          parsed = Oj.load(cleaned, symbol_keys: true)

          # Handle error response
          if parsed[:error] && parsed[:entries]&.empty?
            return { error: parsed[:error] }
          end

          parsed
        rescue Oj::ParseError => e
          $logger.error("Failed to parse LLM JSON response: #{e.message}")
          $logger.error("Raw response: #{text}")
          { error: "I couldn't understand my own response. Please try again." }
        end

        def validate_users(entries, unknown_mentions)
          bot_id = SlackClient.bot_user_id
          unknown = unknown_mentions&.dup || []

          entries.each do |entry|
            user_id = entry[:user_id]
            next if user_id.nil?
            next if user_id == bot_id  # Skip the bot itself

            unless UserService.valid_slack_user?(user_id)
              unknown << user_id
            end
          end

          unknown.uniq
        end
      end
    end
  end
end
