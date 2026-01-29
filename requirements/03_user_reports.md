# Requirement: User Reports

## Description

Any user can generate a personal time report using the `/report` slash command.

## Command

```
/report
```

No arguments required.

## Output Format

CSV file with:
- **Rows:** Projects (alphabetically sorted)
- **Columns:** Months (chronologically, all months with entries)
- **Final column:** Total hours per project
- **Final row:** Total hours per month

## Example Output

```csv
Project,Jan 2026,Feb 2026,Total
Monkey,10.5,8,18.5
Mushroom,20,15.5,35.5
TOTAL,30.5,23.5,54
```

## Delivery

- CSV uploaded as file attachment
- Sent as ephemeral message (only visible to requesting user)
- Posted in the channel where command was invoked

## Edge Cases

- No entries: Return friendly message "You don't have any time entries yet"
- Hours stored as minutes internally, displayed as decimal hours (e.g., 90 min = 1.5)

## Acceptance Criteria

- [x] `/report` command works from any channel or DM
- [x] CSV contains all projects user has logged time on
- [x] CSV contains all months with entries
- [x] Hours are displayed as decimals, not minutes
- [x] Report is ephemeral (only visible to user)
- [x] Empty state is handled gracefully
