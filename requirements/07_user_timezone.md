# Requirement: User Timezone Support

## Description

The bot respects each user's timezone when parsing date references like "today" or "yesterday".

## Timezone Source

User timezone is retrieved from Slack's `users.info` API and cached in the database.

## Caching Strategy

1. On first interaction, fetch timezone from Slack API
2. Store in `users` table with `slack_user_id`
3. Refresh timezone if last update was > 24 hours ago
4. Use `DEFAULT_TIMEZONE` env var as fallback (default: `America/Los_Angeles`)

## Date Interpretation

When user says "today":
- Use current date in **user's timezone**, not server timezone
- Example: At 11pm LA time (7am UTC next day), "today" = LA date

## LLM Context

The system prompt includes:
- Current datetime in user's timezone
- User's IANA timezone name
- Requesting user's Slack ID (for self-references like "I" or "me")

This allows the LLM to correctly interpret relative dates and self-references.

## Fallback Behavior

If timezone cannot be retrieved:
1. Use cached value if available
2. Fall back to `DEFAULT_TIMEZONE` environment variable
3. Default to `America/Los_Angeles` if env var not set

## Acceptance Criteria

- [x] User timezone is fetched from Slack API
- [x] Timezone is cached in database
- [x] Cached timezone is refreshed after 24 hours
- [x] LLM receives datetime in user's timezone
- [x] LLM receives requesting user's Slack ID for self-references
- [x] Fallback to default timezone works
- [x] Invalid timezones don't crash the bot
