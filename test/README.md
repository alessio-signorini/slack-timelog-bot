# Tests

This directory contains all tests for the Slack Timelog Bot.

## Structure

```
test/
├── test_helper.rb           # Common test setup and helpers
├── requirements/            # Functional tests (one per requirement)
│   ├── time_entry_parsing_test.rb
│   ├── project_management_test.rb
│   ├── user_reports_test.rb
│   ├── team_reports_test.rb
│   └── ...
└── integration/             # Integration tests for Slack API contracts
    └── slack_api_test.rb
```

## Running Tests

```bash
# Run all tests
bundle exec rake test

# Run only requirement tests
bundle exec rake test:requirements

# Run only integration tests
bundle exec rake test:integration

# Run a specific test file
bundle exec ruby -Itest test/requirements/time_entry_parsing_test.rb

# Run a specific test
bundle exec ruby -Itest test/requirements/time_entry_parsing_test.rb -n test_parses_simple_time_entry
```

## Test Philosophy

### Requirement Tests

Each requirement file in `requirements/` has a corresponding test file that verifies:
- Happy path works as documented
- Edge cases are handled
- Error conditions are graceful

These tests **mock the LLM** at the `MessageParser` level to test application logic without hitting the Anthropic API.

### Integration Tests

Integration tests verify that:
- Slack request/response JSON schemas are correct
- HMAC signature verification works
- URL verification challenge is handled
- Error responses have correct format

These tests use `Rack::Test` to make real HTTP requests to the app.

## Mocking Strategy

- **LLM responses:** Mocked at the `MessageParser.parse` level
- **Slack API calls:** Stubbed using WebMock
- **Database:** Uses SQLite test database, cleaned between tests

## Adding Tests

When adding a new feature:

1. Add/update requirement in `requirements/`
2. Add test cases in `test/requirements/`
3. If API contracts change, update `test/integration/`
