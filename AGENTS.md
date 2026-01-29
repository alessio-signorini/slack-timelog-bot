# Agent Context & Guidelines

> **Purpose**: Optimized reference for Claude Sonnet 4.5 working on slack-timelog-bot codebase
> **Architecture**: Ruby 3.3, Sinatra 4.0, Puma 6.6, SQLite on Fly.io, Sequel ORM, Anthropic API

---

## 🔴 CRITICAL: Core Patterns (Read First)

### Database Constant Reference
```ruby
DB  # ✅ Always use this (defined in config/database.rb)
TimelogBot::DB  # ❌ Never use this
```

### Data Key Format
```ruby
entry[:user_id]    # ✅ Symbol keys (Oj.load uses symbol_keys: true)
entry['user_id']   # ❌ String keys return nil
```

### Logger Initialization Order
```ruby
# ✅ Correct order for any script
$logger = Logger.new($stdout)
require_relative 'config/environment'

# ❌ Wrong - database.rb expects $logger to exist
require_relative 'config/environment'
$logger = Logger.new($stdout)
```

### LLM Response Access
```ruby
response['content'][0]['text']  # ✅ Hash access (ruby-anthropic gem)
response.content[0].text        # ❌ No object methods
```

---

## 🟠 Architecture Decisions

### Async Slash Command Pattern

**Rule**: Long-running slash commands (`/log`, `/team_log`) use immediate acknowledgment + async response

**Why**: Slack requires slash command responses within 3 seconds. Database queries can take longer, especially on cold starts, causing "operation_timeout" errors.

**Implementation**:
```ruby
# 1. Immediately return acknowledgment (< 3 sec)
def handle_log_async(user_id:, channel_id:, text:, response_url:)
  Thread.new do
    result = handle_log(user_id: user_id, channel_id: channel_id, text: text)
    Services::SlackClient.post_to_response_url(response_url, Oj.load(result, symbol_keys: true))
  end
  
  { response_type: 'ephemeral', text: '⏳ Processing your request...' }.to_json
end

# 2. Process data in background thread
# 3. Post result to response_url when ready
```

**Testing Pattern**:
- With `response_url` → Returns "Processing..." immediately, posts async
- Without `response_url` → Falls back to synchronous processing (for tests)

### SQLite + Fly.io Migration Strategy

**Rule**: Migrations run at app startup, NOT via `release_command`

**Why**: Fly.io's `release_command` uses ephemeral machines. With SQLite on volumes:
1. Release machine creates tables → destroyed immediately
2. App machine starts → empty database → errors

**Implementation** (`config/environment.rb`):
```ruby
# After database.rb load, before models
if ENV['RACK_ENV'] == 'production'
  Sequel.extension :migration
  Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))
  $logger.info('Database migrations completed on startup')
end
```

**Deployment Verification**:
```bash
fly deploy
curl https://slack-timelog-bot.fly.dev/health  # Should return 200
fly logs | grep "Database migrations completed"
fly logs | grep "no such table"  # Should be empty
```

---

## 🟡 LLM Integration

### API Call Pattern (ruby-anthropic v0.4.2+)

```ruby
client = Anthropic::Client.new(access_token: ENV['ANTHROPIC_API_KEY'])
response = client.messages(
  parameters: {
    model: 'claude-haiku-4.5',  # Pass model string directly
    max_tokens: 4096,
    system: system_prompt,
    messages: [{ role: 'user', content: user_message }]
  }
)
text = response['content'][0]['text']  # Returns Hash, not object
```

### System Prompt Requirements

**REQUIRED Context Variables**:
```ruby
system_prompt = llm.build_system_prompt(
  current_datetime: formatted_time,      # For relative time ("yesterday")
  user_timezone: user.timezone,          # For date calculations
  requesting_user_id: user.slack_user_id, # ⚠️ CRITICAL for "I"/"me" resolution
  project_list: projects.join(', ')      # Known project names
)
```

**Why `requesting_user_id` is critical**:
| User Input | Without ID | With ID |
|------------|-----------|---------|
| "I worked 3 hours" | ❌ Can't determine user | ✅ Uses requesting_user_id |
| "me and @john" | ❌ Only gets @john | ✅ Gets both users |
| "we spent 2 hours" | ❌ Ambiguous | ✅ Includes requester |

### XML Prompt Structure (Claude Best Practice)

**Use XML tags for all prompts** (Claude is trained on this format):

```xml
<context>
  <current_datetime>{{current_datetime}}</current_datetime>
  <user_timezone>{{user_timezone}}</user_timezone>
  <requesting_user_id>{{requesting_user_id}}</requesting_user_id>
  <known_projects>{{project_list}}</known_projects>
</context>

<task>
Parse time entry and extract: users, duration, project, date, notes
</task>

<rules>
  <time_parsing>
  - Support "3h", "3 hours", "3:00"
  - Relative dates: "yesterday", "last Friday"
  </time_parsing>
  
  <user_extraction>
  - "I" → use requesting_user_id
  - "@username" → resolve to Slack user ID
  </user_extraction>
</rules>

<output_format>
JSON array of entries with symbol keys
</output_format>

<examples>
  <example>
    <input>"I worked 3 hours on Mushroom yesterday"</input>
    <output>[{user_id: "U123", minutes: 180, project: "Mushroom", ...}]</output>
  </example>
</examples>
```

**Benefits**: Clearer boundaries, better instruction following, consistent parsing

---

## 🟢 Data Patterns

### Symbol Keys (Universal Pattern)

**Rule**: Use symbol keys everywhere in this codebase.

**Why**: `Oj.load(json, symbol_keys: true)` parses all LLM responses with symbol keys.

```ruby
# ✅ Correct
entry[:user_id]
entry[:minutes]
entry[:project]

# ❌ Wrong - returns nil
entry['user_id']
entry['minutes']
```

**Applies to**:
- LLM response parsing
- Event handler processing
- Test mocks/stubs
- Database query results (via Sequel)

### Original Message Auditing

Store raw Slack messages for debugging LLM parsing issues:

```ruby
TimeEntry.create(
  user_id: user.id,
  project_id: project.id,
  minutes: 180,
  date: Date.today,
  notes: 'Task description',
  logged_by_slack_id: requesting_user_id,
  original_message: raw_slack_message_text  # ← Debugging aid
)
```

Schema: `original_message` column is nullable text field.

---

## 🔧 Development Workflows

### Running Tests

```bash
rake test                                           # All tests
ruby -Itest test/requirements/llm_integration_test.rb  # Specific file
```

### Database Utilities

```bash
ruby db/utils/list_table.rb projects 10            # List records
ruby db/utils/update_record.rb projects 1 name="NewName"  # Update
ruby db/utils/delete_record.rb time_entries 123 --force   # Delete
```

### Deployment & Monitoring

```bash
fly deploy                                          # Deploy to production
fly logs                                            # Stream logs
fly logs | grep "Database migrations completed"    # Verify migration
curl https://slack-timelog-bot.fly.dev/health     # Health check
```

---

## ⚡ Quick Decision Trees

### "When do I run migrations?"

```
Are you in production? 
├─ YES → Migrations run at app startup (config/environment.rb)
└─ NO → Are you running tests?
   ├─ YES → Migrations run in test_helper.rb before models load
   └─ NO → Migrations run when you start dev server
```

### "How do I access database?"

```
Use: DB (constant)
├─ Defined in: config/database.rb
├─ Available: After require_relative 'config/environment'
└─ Never use: TimelogBot::DB
```

### "What key type for this hash?"

```
Is data from LLM or Oj.load?
├─ YES → Symbol keys (entry[:user_id])
└─ NO → Still use symbols for consistency
```

### "Where does $logger need to be initialized?"

```
In utility scripts (db/utils/*.rb)?
├─ YES → Initialize $logger BEFORE require_relative 'config/environment'
└─ NO → Logger auto-initialized in config/environment.rb
```

---

## 🚨 Common Pitfalls & Solutions

| Problem | Wrong | Right | Why |
|---------|-------|-------|-----|
| Hash access | `response.content` | `response['content']` | ruby-anthropic returns Hash |
| Key type | `entry['user_id']` | `entry[:user_id]` | Oj uses symbol_keys: true |
| DB constant | `TimelogBot::DB` | `DB` | Top-level constant in database.rb |
| Missing user context | No `requesting_user_id` | Pass to `build_system_prompt()` | LLM can't resolve "I"/"me" |
| Logger order | After environment load | Before environment load | database.rb expects $logger |
| Migration timing | In release_command | At app startup | Fly.io release machines are ephemeral |

---

## 📁 File Organization

```
app/
├── handlers/           # HTTP endpoint handlers
│   ├── event_handler.rb       # Slack events (app_mention)
│   ├── slash_command_handler.rb  # /timelog commands
│   └── interactive_handler.rb    # Button/dialog actions
├── models/            # Sequel ORM models
│   ├── user.rb
│   ├── project.rb
│   └── time_entry.rb
└── services/          # Business logic
    ├── message_parser.rb      # LLM integration
    ├── report_generator.rb    # Report formatting
    ├── slack_client.rb        # Slack API wrapper
    └── anthropic_client.rb    # Anthropic API wrapper

config/
├── database.rb        # DB connection (defines DB constant)
└── environment.rb     # Loads all dependencies + runs migrations

db/
├── migrations/        # Sequel migrations (001_*, 002_*)
└── utils/            # Database management scripts

prompts/
├── anthropic_haiku.txt    # Haiku model prompt
└── anthropic_sonnet.txt   # Sonnet model prompt

test/
├── requirements/      # Unit tests (one per requirement)
└── integration/       # End-to-end tests
```

---

## 🔑 Environment Variables

| Variable | Required | Purpose | Example |
|----------|----------|---------|---------|
| `ANTHROPIC_API_KEY` | ✅ | LLM API access | `sk-ant-...` |
| `LLM_MODEL` | ✅ | Model selection | `anthropic/claude-haiku-4.5` |
| `SLACK_BOT_TOKEN` | ✅ | Slack API | `xoxb-...` |
| `SLACK_SIGNING_SECRET` | ✅ | Request verification | `abc123...` |
| `REPORT_ADMINS` | Optional | Admin Slack IDs | `U123,U456` |
| `DEFAULT_TIMEZONE` | Optional | Fallback TZ | `America/Los_Angeles` |
| `RACK_ENV` | Optional | Environment | `production`/`development`/`test` |

---

## 📝 Testing Strategy

### Test Organization

**Unit Tests** (`test/requirements/`):
- Isolated business logic
- Mock external dependencies (Slack, LLM)
- Fast execution
- One file per requirement document

**Integration Tests** (`test/integration/`):
- Full request/response cycle
- Real test database
- HTTP endpoint verification
- End-to-end workflows

### Mock Patterns

```ruby
# Slack API
stub_slack_api  # Helper from test_helper.rb
TimelogBot::Services::SlackClient.stubs(:post_message).returns(true)

# LLM Responses (use symbol keys!)
TimelogBot::Services::MessageParser.stubs(:parse).returns({
  entries: [
    { user_id: 'U123', minutes: 180, project: 'Mushroom', date: '2026-01-28' }
  ]
})
```

### Test Database Setup

```ruby
# test_helper.rb pattern
test_db_path = File.join(__dir__, '..', 'tmp', 'test.db')
FileUtils.rm_f(test_db_path)

DB = Sequel.connect("sqlite://#{test_db_path}")
Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))

# THEN load environment
require_relative '../config/environment'
```

**Order matters**: Migrations → Environment → Models

---

## 🎯 Implementation Checklist

When adding a new feature:

- [ ] Update relevant model in `app/models/`
- [ ] Create migration in `db/migrations/` (sequential numbering)
- [ ] Update service logic in `app/services/`
- [ ] Update handler in `app/handlers/`
- [ ] Update LLM prompt in `prompts/` if needed
- [ ] Add unit test in `test/requirements/`
- [ ] Add integration test if touching HTTP endpoints
- [ ] Update AGENTS.md if introducing new pattern
- [ ] Test locally with `rake test`
- [ ] Deploy with `fly deploy`
- [ ] Verify health endpoint returns 200
- [ ] Check logs for migration success

When debugging LLM issues:

- [ ] Check `original_message` field in database
- [ ] Verify `requesting_user_id` is in system prompt
- [ ] Confirm XML structure in prompt template
- [ ] Test with `test/scripts/test_anthropic.rb`
- [ ] Verify symbol keys in response handling
- [ ] Check timezone context is passed correctly

---

## 💡 Code Examples

### Creating a Time Entry (Full Pattern)

```ruby
# In event_handler.rb
def handle_time_entry(event, requesting_user)
  # 1. Parse with LLM
  result = parser.parse(
    message: event['text'],
    user_timezone: requesting_user.timezone,
    requesting_user_id: requesting_user.slack_user_id
  )
  
  # 2. Process entries (symbol keys!)
  result[:entries].each do |entry|
    user = User.find(slack_user_id: entry[:user_id])
    project = Project.find_or_create(name: entry[:project])
    
    # 3. Create entry with original message
    TimeEntry.create(
      user_id: user.id,
      project_id: project.id,
      minutes: entry[:minutes],
      date: entry[:date],
      notes: entry[:notes],
      logged_by_slack_id: requesting_user.slack_user_id,
      original_message: event['text']  # Audit trail
    )
  end
end
```

### Building System Prompt

```ruby
# In message_parser.rb
def build_system_prompt(current_datetime:, user_timezone:, requesting_user_id:, project_list:)
  template = File.read('prompts/anthropic_haiku.txt')
  
  template
    .gsub('{{current_datetime}}', current_datetime)
    .gsub('{{user_timezone}}', user_timezone)
    .gsub('{{requesting_user_id}}', requesting_user_id)  # Critical!
    .gsub('{{project_list}}', project_list)
end
```

### Utility Script Pattern

```ruby
#!/usr/bin/env ruby
# db/utils/example_script.rb

# 1. Initialize logger FIRST
$logger = Logger.new($stdout)
$logger.level = Logger::INFO

# 2. THEN load environment
require_relative '../../config/environment'

# 3. Now DB constant is available
projects = DB[:projects].all
projects.each { |p| puts p[:name] }
```

