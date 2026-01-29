# Development Container

This project uses a VS Code Dev Container for consistent development environment.

## Prerequisites

- Docker Desktop installed and running
- VS Code with "Dev Containers" extension

## Getting Started

1. Open this project in VS Code
2. When prompted, click "Reopen in Container" (or use Command Palette → "Dev Containers: Reopen in Container")
3. Wait for the container to build (first time takes a few minutes)
4. Copy `.env.example` to `.env` and fill in your tokens

## What's Included

- **Ruby 3.3** with bundler
- **SQLite3** for local database
- **GitHub CLI** for repository management
- **Ruby LSP** extension for code intelligence

## Ports

- **4567**: Sinatra application (default)
- **4040**: ngrok web interface

## Local Development with Slack

Since Slack needs a public HTTPS URL to send events, you need to use ngrok:

```bash
# In one terminal, start the app
bundle exec puma -p 4567

# In another terminal, start ngrok
ngrok http 4567
```

Then configure your Slack app's Event Subscriptions and Interactivity URLs to use the ngrok HTTPS URL.

## Database

Local development uses SQLite stored in `/data/development.db`. The `/data` folder is mounted from your local `./data` directory.

```bash
# Run migrations
bundle exec rake db:migrate

# Seed initial projects
bundle exec rake db:seed
```
