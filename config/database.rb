# frozen_string_literal: true

require 'sequel'
require 'fileutils'

module TimelogBot
  class Database
    class << self
      def connection
        @connection ||= establish_connection
      end

      def establish_connection
        db_path = database_path
        FileUtils.mkdir_p(File.dirname(db_path))

        db = Sequel.sqlite(db_path)

        # Enable WAL mode for better concurrency and reliability
        db.run('PRAGMA journal_mode = WAL')
        db.run('PRAGMA synchronous = NORMAL')
        db.run('PRAGMA foreign_keys = ON')
        db.run('PRAGMA busy_timeout = 5000')

        $logger.info("Connected to database: #{db_path}")
        db
      end

      def database_path
        if ENV['DATABASE_URL']
          ENV['DATABASE_URL']
        elsif ENV['RACK_ENV'] == 'production'
          '/data/production.db'
        elsif ENV['RACK_ENV'] == 'test'
          File.join(__dir__, '..', 'tmp', 'test.db')
        else
          # Local development - use project data directory
          File.join(__dir__, '..', 'data', 'development.db')
        end
      end

      def disconnect
        @connection&.disconnect
        @connection = nil
      end
    end
  end
end

# Establish connection on load (unless already defined, e.g., in tests)
unless defined?(DB)
  DB = TimelogBot::Database.connection
end
