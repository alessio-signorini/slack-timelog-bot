# Requirement: Slack Integration

## Description

The bot must properly integrate with Slack's API, handling events, interactions, and slash commands securely.

## Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /slack/events` | Receive Events API callbacks |
| `POST /slack/interactive` | Handle interactive components |
| `POST /slack/commands` | Receive slash commands |
| `GET /health` | Health check for monitoring |

## Security

All Slack endpoints must verify request authenticity:

1. Check `X-Slack-Request-Timestamp` header (reject if > 5 minutes old)
2. Compute HMAC-SHA256 of `v0:{timestamp}:{body}` using signing secret
3. Compare with `X-Slack-Signature` header
4. Reject unauthorized requests with 401 status

## Required Slack Scopes

- `app_mentions:read` - Read messages that mention the bot
- `chat:write` - Send messages
- `commands` - Add slash commands
- `files:write` - Upload CSV reports
- `im:history` - Read direct messages
- `reactions:write` - Add emoji reactions
- `users:read` - Get user info (timezone)

## Event Subscriptions

- `app_mention` - When bot is @mentioned in a channel
- `message.im` - Direct messages to the bot

## URL Verification

The Events API sends a challenge on initial setup:
```json
{"type": "url_verification", "challenge": "abc123"}
```

Bot must respond with the challenge value as plain text.

## Acceptance Criteria

- [x] All requests are verified using HMAC-SHA256
- [x] Invalid signatures return 401
- [x] Expired timestamps are rejected
- [x] URL verification challenge is handled
- [x] Health endpoint returns 200 with DB check
- [x] Bot responds to both DMs and @mentions
