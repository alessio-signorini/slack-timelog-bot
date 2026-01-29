# frozen_string_literal: true

# Only load full environment for non-db tasks
def load_full_environment
  require_relative 'config/environment'
end

def load_database_only
  require 'bundler/setup'
  Bundler.require(:default)
  require 'dotenv'
  Dotenv.load unless ENV['RACK_ENV'] == 'production'
  require 'logger'
  $logger = Logger.new($stdout)
  $logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'INFO').upcase)
  require_relative 'config/database'
end

namespace :db do
  desc 'Run database migrations'
  task :migrate do
    load_database_only
    require 'sequel/extensions/migration'

    migrations_path = File.join(__dir__, 'db', 'migrations')
    Sequel::Migrator.run(DB, migrations_path)

    $logger.info('Migrations completed successfully')
  end

  desc 'Rollback the last migration'
  task :rollback do
    load_database_only
    require 'sequel/extensions/migration'

    migrations_path = File.join(__dir__, 'db', 'migrations')
    version = DB[:schema_migrations].order(Sequel.desc(:filename)).first
    
    if version
      target = version[:filename].to_i - 1
      Sequel::Migrator.run(DB, migrations_path, target: target)
      $logger.info("Rolled back to version #{target}")
    else
      $logger.info('Nothing to rollback')
    end
  end

  desc 'Seed the database with initial data'
  task :seed do
    load_full_environment
    load File.join(__dir__, 'db', 'seeds.rb')
    $logger.info('Database seeded successfully')
  end

  desc 'Reset database (drop all tables, migrate, seed)'
  task reset: [:drop, :migrate, :seed]

  desc 'Drop all tables'
  task :drop do
    load_database_only
    DB.tables.each do |table|
      DB.drop_table(table, cascade: true)
    end
    $logger.info('All tables dropped')
  end

  desc 'Show current migration version'
  task :version do
    load_database_only
    require 'sequel/extensions/migration'
    version = Sequel::Migrator.get_current_migration_version(DB)
    puts "Current schema version: #{version}"
  end
end

namespace :test do
  desc 'Run all tests'
  task :all do
    # Don't load environment here - test_helper handles DB setup
    $LOAD_PATH.unshift File.join(__dir__, 'test')
    require 'test_helper'
    Dir.glob('./test/**/*_test.rb').each { |f| require f }
  end

  desc 'Run requirement tests'
  task :requirements do
    # Don't load environment here - test_helper handles DB setup
    $LOAD_PATH.unshift File.join(__dir__, 'test')
    require 'test_helper'
    Dir.glob('./test/requirements/**/*_test.rb').each { |f| require f }
  end

  desc 'Run integration tests'
  task :integration do
    # Don't load environment here - test_helper handles DB setup
    $LOAD_PATH.unshift File.join(__dir__, 'test')
    require 'test_helper'
    Dir.glob('./test/integration/**/*_test.rb').each { |f| require f }
  end
end

desc 'Run all tests'
task test: 'test:all'

desc 'Start the development server with auto-reload'
task :dev do
  exec 'rerun --pattern "**/*.rb" -- bundle exec puma -p 4567'
end

desc 'Start the production server'
task :start do
  exec 'bundle exec puma -p 8080'
end

task default: :test
