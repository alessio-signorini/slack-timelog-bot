# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2'

# Web framework
gem 'sinatra', '~> 4.0'
gem 'puma', '~> 6.4'
gem 'rack', '~> 3.0'

# Database
gem 'sequel', '~> 5.77'
gem 'sqlite3', '~> 1.7'

# Slack API
gem 'slack-ruby-client', '~> 2.3'
gem 'faraday', '~> 2.9'

# Anthropic LLM
gem 'ruby-anthropic', '~> 0.4.2'

# Environment management
gem 'dotenv', '~> 3.1'

# JSON parsing (faster than stdlib)
gem 'oj', '~> 3.16'

# Rake for database migrations
gem 'rake', '~> 13.1'

group :development do
  gem 'rerun', '~> 0.14'
  gem 'ruby-lsp', '~> 0.22', require: false
end

group :test do
  gem 'minitest', '~> 5.22'
  gem 'rack-test', '~> 2.1'
  gem 'webmock', '~> 3.23'
  gem 'mocha', '~> 2.1'
end

gem "csv", "~> 3.3"
