# Requirement: Time Entry Parsing

## Description

The bot must be able to receive natural language messages from users and parse them into structured time entries.

## Input

A Slack message (via DM or @mention) containing:
- One or more user mentions (e.g., `<@U12345678>`) or self-references ("I", "me")
- A time duration (e.g., "3 hours", "2h 30min", "1.5h", "90 minutes")
- A project name (may be fuzzy match to known projects)
- An optional date reference (defaults to "today")
- Optional notes about tasks performed

## Expected Behavior

1. Parse the message using the configured LLM
2. Extract user IDs, duration (in minutes), project, date, and notes
3. Store the original message text for debugging purposes
4. Create **separate time entries for each user mentioned**
5. If project confidence < 70%, prompt user to select from known projects
6. If mentioned users are invalid, inform the user
7. On success, add ✅ reaction to the original message

## Examples

**Input:** `<@U123> and <@U456> spent 3 hours working on project Mushroom today on tasks like finishing data gap document`

**Result:** Two time entries:
- User U123: 180 minutes on Mushroom
- User U456: 180 minutes on Mushroom

**Input:** `I worked 2.5 hours on monkey yesterday`

**Result:** One time entry for the requesting user: 150 minutes on Monkey

## Database Schema

Each time entry is stored with:
- `user_id` - Foreign key to users table
- `project_id` - Foreign key to projects table
- `minutes` - Duration as integer (e.g., 180 for 3 hours)
- `date` - Date of work (YYYY-MM-DD)
- `notes` - Optional task description
- `logged_by_slack_id` - Slack ID of who created the entry
- `original_message` - Original Slack message text (for debugging)
- `logged_at` - Timestamp when entry was created

## Acceptance Criteria

- [x] Fractional hours are supported (stored as minutes)
- [x] Multiple users create multiple entries
- [x] Date parsing works for "today", "yesterday", relative days
- [x] Unknown projects trigger project selection dropdown
- [x] Invalid user mentions are reported
- [x] Success is indicated with emoji reaction
- [x] Original message text is stored in `time_entries.original_message` for debugging
