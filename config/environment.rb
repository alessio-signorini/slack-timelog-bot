# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development').to_sym)

require 'dotenv'
Dotenv.load unless ENV['RACK_ENV'] == 'production'

require 'json'
require 'csv'
require 'time'
require 'logger'

# Configure logging
$logger = Logger.new($stdout)
$logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'INFO').upcase)
$logger.formatter = proc do |severity, datetime, _, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

# Load database configuration
require_relative 'database'

# Run migrations in production before loading models
if ENV['RACK_ENV'] == 'production'
  Sequel.extension :migration
  Sequel::Migrator.run(DB, File.join(__dir__, '..', 'db', 'migrations'))
  $logger.info('Database migrations completed on startup')
end

# Load all application files
Dir[File.join(__dir__, '..', 'app', 'helpers', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'models', '*.rb')].sort.each { |f| require f }

# Load services in dependency order
require File.join(__dir__, '..', 'app', 'services', 'llm_provider')
Dir[File.join(__dir__, '..', 'app', 'services', '*.rb')].sort.each { |f| require f }

Dir[File.join(__dir__, '..', 'app', 'handlers', '*.rb')].sort.each { |f| require f }
