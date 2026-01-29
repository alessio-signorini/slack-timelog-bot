# LLM Prompts for Time Parsing

This directory contains the prompts used to parse natural language time entries.

## Files

- **anthropic_haiku.txt** - Prompt optimized for Claude Haiku 4.5 (faster, cheaper)
- **anthropic_sonnet.txt** - Prompt optimized for Claude Sonnet 4.5 (more accurate)

## Template Variables

The prompts contain placeholders that are replaced at runtime:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{current_datetime}}` | Current date/time in user's timezone | `2026-01-27 14:30:00 PST` |
| `{{user_timezone}}` | User's IANA timezone | `America/Los_Angeles` |
| `{{project_list}}` | Comma-separated known projects | `Monkey, Barometer, Mushroom, ...` |

## Model Differences

### Haiku (claude-haiku-4.5)
- Faster response times (~200-500ms)
- Lower cost (~$0.00025/1K input, $0.00125/1K output)
- Good for straightforward messages
- May need clearer instructions

### Sonnet (claude-sonnet-4.5)
- Slower but more thorough (~500-1500ms)
- Higher cost (~$0.003/1K input, $0.015/1K output)
- Better at ambiguous cases
- More nuanced understanding

## Iterating on Prompts

When modifying prompts:

1. **Test with examples** - Use the test suite in `test/requirements/`
2. **Check edge cases** - Ambiguous dates, fuzzy project names, multiple users
3. **Monitor confidence scores** - If too many entries need clarification, adjust matching
4. **Keep it concise** - Shorter prompts = faster responses = lower cost

## Output Schema

Both prompts should produce identical JSON output:

```json
{
  "entries": [
    {
      "user_id": "U12345678",
      "minutes": 180,
      "project": "Project Name",
      "project_confidence": 95,
      "date": "2026-01-27",
      "notes": "Description of work"
    }
  ],
  "needs_clarification": false,
  "suggested_project_name": "raw text",
  "unknown_user_mentions": []
}
```

## Adding New Providers

To add a new LLM provider:

1. Create a new prompt file: `prompts/{provider}_{model}.txt`
2. Implement provider in `app/services/llm/{provider}_client.rb`
3. Update `LLMProviderFactory` to recognize the new provider
4. Test thoroughly with the existing test suite
