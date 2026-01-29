# Requirement: Team Reports

## Description

Authorized users (report admins) can generate team-wide reports for a specific month.

## Command

```
/team_report [YYYY-MM]
```

- If month is omitted, defaults to current month
- Examples: `/team_report`, `/team_report 2026-01`

## Authorization

Only users listed in `REPORT_ADMINS` environment variable can run this command.

- Format: Comma-separated Slack user IDs
- Example: `REPORT_ADMINS=U12345678,U87654321`

Non-authorized users receive: "Sorry, you don't have permission to run team reports. Contact an admin if you need access."

## Output Format

CSV file with:
- **Rows:** Users (sorted alphabetically by display name)
- **Columns:** Projects (alphabetically sorted)
- **Final column:** Total hours per user
- **Final row:** Total hours per project

## Example Output

```csv
User,Monkey,Mushroom,Total
Alice,10.5,20,30.5
Bob,8,15.5,23.5
TOTAL,18.5,35.5,54
```

## Delivery

- CSV uploaded as file attachment
- Posted in the channel where command was invoked
- Visible only to the requesting user (ephemeral)

## Acceptance Criteria

- [x] Only report admins can run `/team_report`
- [x] Unauthorized users get friendly error message
- [x] Month argument is optional (defaults to current)
- [x] CSV contains all users who logged time that month
- [x] CSV contains all projects with entries that month
- [x] Hours are displayed as decimals
- [x] Empty month returns friendly message
