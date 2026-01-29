# Deployment Guide

This guide walks you through deploying the Slack Timelog Bot to Fly.io.

## Prerequisites

- [Fly.io CLI](https://fly.io/docs/hands-on/install-flyctl/) installed
- A Fly.io account (`fly auth login`)
- [Anthropic API key](https://console.anthropic.com/)

---

## Part 1: Create Slack App

### Step 1: Create the App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **"Create New App"**
3. Choose **"From scratch"**
4. Enter:
   - **App Name:** `Timelog Bot` (or your preference)
   - **Workspace:** Select your workspace
5. Click **"Create App"**

### Step 2: Add App Description

1. In the left sidebar, click **"Basic Information"**
2. Scroll to **"Display Information"**
3. Fill in the descriptions:
   
   **Short Description:**
   ```
   Log your work hours naturally. Just tell the bot what you did, and it tracks time by project.
   ```
   
   **Long Description:**
   ```
   Timelog Bot makes time tracking effortless. Simply message the bot in natural language like "I spent 3 hours on the Monkey project working on data analysis" and it automatically logs your time. No forms, no spreadsheets.

   Features:
   • Natural language time logging - just describe your work
   • Automatic project detection and classification
   • Personal time reports with /report command
   • Team reports for managers with /team_report
   • Works in direct messages or by @mentioning the bot
   • Supports retroactive logging (yesterday, last Monday, etc.)
   • Multi-user logging from a single message
   • Export reports as CSV files

   Perfect for teams that want simple time tracking without interrupting their workflow.
   ```

4. Optionally add an app icon (512x512 PNG recommended)
5. Click **"Save Changes"**

### Step 3: Configure Bot Token Scopes

1. In the left sidebar, click **"OAuth & Permissions"**
2. Scroll to **"Scopes"** → **"Bot Token Scopes"**
3. Click **"Add an OAuth Scope"** and add these scopes:
   - `app_mentions:read` - Read messages that mention the bot
   - `chat:write` - Send messages
   - `commands` - Add slash commands
   - `files:write` - Upload CSV reports
   - `im:history` - Read direct messages
   - `reactions:write` - Add emoji reactions
   - `users:read` - Get user info (timezone)

### Step 4: Install to Workspace

1. Scroll up to **"OAuth Tokens for Your Workspace"**
2. Click **"Install to Workspace"**
3. Review permissions and click **"Allow"**
4. Copy the **"Bot User OAuth Token"** (starts with `xoxb-`)
   - Save this! You'll need it as `SLACK_BOT_TOKEN`

### Step 5: Get Signing Secret

1. In the left sidebar, click **"Basic Information"**
2. Scroll to **"App Credentials"**
3. Copy the **"Signing Secret"**
   - Save this! You'll need it as `SLACK_SIGNING_SECRET`

### Step 6: Enable Events (Configure After Deployment)

We'll come back to this after deploying to get the URL.

---

## Part 2: Deploy to Fly.io

### Step 1: Create Fly.io App

```bash
# Navigate to your project directory
cd slack-timelog-bot

# Create the app (choose a unique name)
fly apps create slack-timelog-bot
```

If the name is taken, choose another:
```bash
fly apps create my-timelog-bot
```

Then update `fly.toml`:
```toml
app = "my-timelog-bot"
```

### Step 2: Create Storage Volume

The bot needs persistent storage for SQLite:

```bash
fly volumes create timelog_data --size 1 --region lax
```

Notes:
- `--size 1` = 1 GB (plenty for time entries, also the minimum)
- `--region lax` = Los Angeles, CA (change to your preferred region)
- See regions: `fly platform regions`

### Step 3: Set Secrets

```bash
# Slack credentials (from Part 1)
fly secrets set SLACK_SIGNING_SECRET="your_signing_secret"
fly secrets set SLACK_BOT_TOKEN="xoxb-your-bot-token"

# Anthropic API key
fly secrets set ANTHROPIC_API_KEY="sk-ant-your-api-key"
```

### Step 4: Configure Environment Variables

Edit `fly.toml` and update the `[env]` section:

```toml
[env]
  RACK_ENV = "production"
  PORT = "8080"
  LOG_LEVEL = "INFO"  # or DEBUG for more verbose logs
  LLM_MODEL = "anthropic/claude-haiku-4.5"  # or claude-sonnet-4.5 for better accuracy
  REPORT_ADMINS = "U12345678,U87654321"  # Your Slack user IDs (find via profile → More → Copy member ID)
```

### Step 5: Deploy

```bash
fly deploy
```

First deployment takes 2-3 minutes. Watch for:
- ✓ Building image
- ✓ Deploying image
- ✓ Health checks passing

### Step 6: Run Database Migrations

Database migrations run automatically on each deployment via the `release_command` in `fly.toml`.

If you need to seed the database with initial projects, run:

```bash
fly ssh console -C "bundle exec rake db:seed"
```

### Step 7: Verify Deployment

```bash
# Check app status
fly status

# Check logs
fly logs

# Test health endpoint
curl https://your-app-name.fly.dev/health
```

---

## Part 3: Configure Slack Events

Now that your app is deployed, configure Slack to send events to it.

### Step 1: Enable Event Subscriptions

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → Your app
2. Click **"Event Subscriptions"** in the left sidebar
3. Toggle **"Enable Events"** to ON
4. Enter your **Request URL:**
   ```
   https://your-app-name.fly.dev/slack/events
   ```
5. Wait for the ✓ "Verified" checkmark

### Step 2: Subscribe to Bot Events

Under **"Subscribe to bot events"**, click **"Add Bot User Event"** for each:
- `app_mention` - When someone @mentions the bot
- `message.im` - Direct messages to the bot

Click **"Save Changes"**

### Step 3: Enable Direct Messaging

1. Click **"App Home"** in the left sidebar
2. Scroll to the **"Show Tabs"** section
3. Under **"Messages Tab"**, toggle **"Allow users to send Slash commands and messages from the messages tab"** to **ON**
4. A checkbox will appear - check **"Allow users to send messages from the messages tab"**

This allows users to send direct messages to your bot.

### Step 4: Configure Interactivity (Required for Project Selection)

1. Click **"Interactivity & Shortcuts"** in the left sidebar
2. Toggle **"Interactivity"** to ON
3. Enter your **Request URL:**
   ```
   https://your-app-name.fly.dev/slack/interactive
   ```
4. Click **"Save Changes"**

**Why this is required:** When the bot can't recognize a project name, it shows a dropdown menu for you to select the correct project or create a new one. Without this URL configured, you'll see an error: "This app is not configured to handle interactive responses."

### Step 5: Create Slash Commands

1. Click **"Slash Commands"** in the left sidebar
2. Click **"Create New Command"**
3. Create `/report`:
   - **Command:** `/report`
   - **Request URL:** `https://your-app-name.fly.dev/slack/commands`
   - **Short Description:** `Get your personal time report`
   - Click **"Save"**

4. Create `/team_report`:
   - **Command:** `/team_report`
   - **Request URL:** `https://your-app-name.fly.dev/slack/commands`
   - **Short Description:** `Get team time report (admins only)`
   - **Usage Hint:** `[YYYY-MM]`
   - Click **"Save"**

5. Create `/log`:
   - **Command:** `/log`
   - **Request URL:** `https://your-app-name.fly.dev/slack/commands`
   - **Short Description:** `View your time entries from the last 60 days`
   - **Usage Hint:** `[days]`
   - Click **"Save"**

6. Create `/team_log`:
   - **Command:** `/team_log`
   - **Request URL:** `https://your-app-name.fly.dev/slack/commands`
   - **Short Description:** `View all team time entries (admins only)`
   - **Usage Hint:** `[days]`
   - Click **"Save"**

7. Create `/delete`:
   - **Command:** `/delete`
   - **Request URL:** `https://your-app-name.fly.dev/slack/commands`
   - **Short Description:** `Delete a time entry by ID`
   - **Usage Hint:** `[entry_id]`
   - Click **"Save"**

### Step 6: Reinstall App

After adding event subscriptions and slash commands:

1. Go to **"OAuth & Permissions"**
2. Click **"Reinstall to Workspace"**
3. Click **"Allow"**

---

## Part 4: Test Your Bot

### Test Time Logging

In Slack, try:

1. **Direct message the bot:**
   ```
   I spent 3 hours on Monkey today working on data analysis
   ```

2. **Mention in a channel:**
   ```
   @Timelog Bot <@U12345678> and I worked 2.5 hours on Mushroom yesterday
   ```

3. **Look for the ✅ reaction** - means it was logged!

### Test Reports

```
/report
```

Get a CSV export of all your time entries.

```
/team_report 2026-01
```

Get a CSV export of all team time entries for January 2026 (admins only).

```
/log
```

View your last 60 days of time entries (default), or specify the number of days:
```
/log 30
```

Shows a formatted list with:
- Entry ID (for reference)
- Date of work
- User who worked
- Who logged the entry
- Project name
- Hours spent
- Notes

```
/team_log
```

View all team time entries from the last 60 days (admins only):
```
/team_log 30
```

Shows entries from all users with the same format as `/log`.

---

## Troubleshooting

### Bot doesn't respond

```bash
# Check logs
fly logs

# Common issues:
# - Invalid SLACK_BOT_TOKEN
# - Event subscriptions not enabled
# - Wrong Request URL
```

### "Unauthorized" errors

```bash
# Verify signing secret is correct
fly secrets list

# Re-set if needed
fly secrets set SLACK_SIGNING_SECRET="correct_secret"
```

### Database errors

```bash
# Connect to app and check database
fly ssh console

# Inside the console:
bundle exec rake db:migrate
bundle exec rake db:seed
```

### "Rate limit" errors

The bot has automatic retry logic, but if you see persistent rate limits:
- Switch to a higher-tier Anthropic plan
- Use `claude-haiku-4.5` instead of `claude-sonnet-4.5`

---

## Local Development with ngrok

For testing changes locally:

### 1. Start ngrok

```bash
ngrok http 4567
```

Copy the HTTPS URL (e.g., `https://abc123.ngrok.io`)

### 2. Update Slack URLs temporarily

Go to your Slack app settings and update:
- Event Subscriptions Request URL
- Interactivity Request URL  
- Slash Command URLs

To use your ngrok URL instead of the Fly.io URL.

### 3. Start local server

```bash
# Copy environment file
cp .env.example .env
# Edit .env with your tokens

# Run migrations
bundle exec rake db:migrate
bundle exec rake db:seed

# Start server
bundle exec puma -p 4567
```

### 4. Test in Slack

Now messages will hit your local server!

**Remember:** Restore the Fly.io URLs when done testing.

---

## Updating the Bot

```bash
# Make changes, then deploy
fly deploy

# If you changed migrations
fly ssh console -C "bundle exec rake db:migrate"
```

---

## Monitoring

```bash
# View logs in real-time
fly logs

# Check app status
fly status

# SSH into the container
fly ssh console

# Check database
fly ssh console -C "sqlite3 /data/production.db '.tables'"
```

---

## Costs

Fly.io costs for this setup:

- **Compute:** ~$0-2/month (auto-stop when idle)
- **Volume:** $0.15/GB/month = ~$0.15/month
- **Total:** < $3/month for typical usage

Anthropic costs:
- **Haiku 4.5:** ~$0.25 per 1M input tokens, $1.25 per 1M output tokens
- **Per request:** ~$0.001 or less
- **Monthly:** A few cents for personal use
