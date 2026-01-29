# Requirement: LLM Integration

## Description

The bot uses an LLM (Language Model) to parse natural language time entries. The implementation supports multiple providers via a generic interface.

## Configuration

LLM provider and model are configured via environment variable:

```
LLM_MODEL=provider/model
```

Examples:
- `anthropic/claude-haiku-4.5`
- `anthropic/claude-sonnet-4.5`

## Provider Interface

All LLM providers must implement:

```ruby
def complete(system_context:, user_message:)
  # Returns parsed response text
end

def build_system_prompt(current_datetime:, user_timezone:, requesting_user_id:, project_list:)
  # Returns formatted system prompt with all context
end
```

**Note:** The `requesting_user_id` is crucial for the LLM to understand self-references like "I", "me", or "we" in messages.

## Anthropic Implementation

- Uses official `ruby-anthropic` gem (v0.4.2+)
- Supports claude-haiku-4.5 (faster, cheaper) and claude-sonnet-4.5 (more accurate)
- Has separate prompt files for each model
- Uses XML-structured prompts for better Claude comprehension
- Implements retry logic for rate limits and connection errors
- Returns user-friendly errors on failure

## Prompt Templates

Located in `prompts/` directory:
- `anthropic_haiku.txt` - Optimized for Haiku
- `anthropic_sonnet.txt` - Optimized for Sonnet

**Prompt Structure:**
- XML-tagged sections: `<context>`, `<task>`, `<rules>`, `<output_format>`, `<examples>`
- Nested XML tags for rule organization (e.g., `<time_parsing>`, `<user_extraction>`)
- XML format improves Claude's ability to follow instructions precisely

**Template Placeholders:**
- `{{current_datetime}}` - Current time in user's timezone
- `{{user_timezone}}` - User's IANA timezone
- `{{requesting_user_id}}` - Slack ID of the user who sent the message
- `{{project_list}}` - Comma-separated known projects

## Error Handling

On LLM failure, bot responds with friendly message:
> "I'm having trouble understanding right now. Please try again in a moment. 🙏"

## Acceptance Criteria

- [x] Provider is selected based on LLM_MODEL env var
- [x] Unknown providers raise clear error
- [x] Anthropic client handles rate limits with retry
- [x] Anthropic client handles connection errors with retry
- [x] Prompt templates are loaded from files
- [x] Prompts use XML structure for better Claude comprehension
- [x] Current datetime is formatted in user's timezone
- [x] Requesting user's Slack ID is included in prompt context
- [x] Project list is included in prompt
- [x] Errors result in user-friendly messages
