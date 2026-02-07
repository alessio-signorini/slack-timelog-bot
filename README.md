# 🤖 Timelog Bot

A simple Slack bot that helps teams track time spent on projects using natural language.

## Features

- **Natural language time logging**: Just tell the bot what you worked on
  - "I spent 3 hours on Mushroom today finishing the data gap document"
  - "@alice and @bob worked 2.5h on Monkey yesterday"
  
- **Fuzzy project matching**: Bot recognizes your projects even with typos
  
- **Personal reports**: `/report` generates a CSV of your time by project/month

- **View entries**: `/log` shows your last 60 days of time entries

- **Delete entries**: `/delete [ID]` removes a time entry (own entries or admin)

- **Team log**: `/team_log` shows all team entries (admin only)

- **Team reports**: `/team_report 2026-01` generates team-wide reports (admin only)

- **Timezone-aware**: Dates are interpreted in each user's Slack timezone

## Quick Start

### Prerequisites

- Ruby 3.2+
- Slack workspace (admin access to create apps)
- [Anthropic API key](https://console.anthropic.com/)
- [Fly.io account](https://fly.io/) (for deployment)

### Local Development

1. **Clone and setup:**
   ```bash
   git clone <repo-url>
   cd slack-timelog-bot
   bundle install
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your tokens
   ```

3. **Setup database:**
   ```bash
   mkdir -p data
   bundle exec rake db:migrate
   bundle exec rake db:seed
   ```

4. **Start the server:**
   ```bash
   bundle exec puma -p 4567
   ```

5. **Expose locally with ngrok:**
   ```bash
   ngrok http 4567
   ```

6. **Configure Slack app** with your ngrok URL (see [DEPLOYMENT.md](DEPLOYMENT.md))

### Using Dev Container

If you have Docker and VS Code:

1. Open project in VS Code
2. Click "Reopen in Container" when prompted
3. Copy `.env.example` to `.env` and configure
4. Run `bundle exec rake db:migrate db:seed`
5. Start with `bundle exec puma -p 4567`

## Usage

### Logging Time

**Direct message the bot:**
```
I worked 3 hours on Mushroom today on data analysis
```

**Mention in a channel:**
```
@Timelog Bot @alice and @bob spent 2h on Barometer yesterday reviewing designs
```

The bot will:
- Parse the message using AI
- Create time entries for mentioned users
- React with ✅ on success
- Ask to select a project if unsure

### Reports

**Personal report:**
```
/report
```
Generates CSV: projects (rows) × months (columns)

**View recent entries:**
```
/log
```
Shows your last 60 days of time entries with ID, date, project, hours, and notes

```
/log 30
```
Shows entries from the last 30 days (accepts 1-365 days)

**Team log (admins only):**
```
/team_log
```
Shows all team members' time entries from the last 60 days

```
/team_log 30
```
Shows team entries from the last 30 days (accepts 1-365 days)

**Delete an entry:**
```
/delete 42
```
Deletes entry #42 (you can only delete your own entries, admins can delete any)

Find entry IDs using `/log` or `/team_log`

**Team report (admins only):******
```
/team_report 2026-01
```
Generates CSV: users (rows) × projects (columns) for that month

## Configuration

| Variable | Description | Example |
|----------|-------------|---------|
| `SLACK_SIGNING_SECRET` | Slack app signing secret | `abc123...` |
| `SLACK_BOT_TOKEN` | Bot OAuth token | `xoxb-...` |
| `LLM_MODEL` | LLM provider/model | `anthropic/claude-haiku-4.5` |
| `ANTHROPIC_API_KEY` | Anthropic API key | `sk-ant-...` |
| `REPORT_ADMINS` | User IDs for team reports | `U123,U456` |
| `DEFAULT_TIMEZONE` | Fallback timezone | `America/Los_Angeles` |

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete instructions on:
- Creating the Slack app
- Deploying to Fly.io
- Setting up webhooks

## Architecture

```
slack-timelog-bot/
├── app.rb                 # Main Sinatra app
├── app/
│   ├── handlers/          # Slack event/command handlers
│   ├── helpers/           # Verification, utilities
│   ├── models/            # Sequel models (User, Project, TimeEntry)
│   └── services/          # Business logic (parser, reports, LLM)
├── config/
│   ├── database.rb        # SQLite + WAL configuration
│   └── environment.rb     # App bootstrap
├── db/
│   ├── migrations/        # Database schema
│   └── seeds.rb           # Initial projects
├── prompts/               # LLM prompt templates
├── requirements/          # Feature specifications
└── test/                  # Tests
```

## Testing

```bash
# All tests
bundle exec rake test

# Requirement tests only
bundle exec rake test:requirements

# Integration tests only
bundle exec rake test:integration
```

## License

MIT
