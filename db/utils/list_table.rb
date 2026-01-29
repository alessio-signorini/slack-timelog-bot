#!/usr/bin/env ruby
# frozen_string_literal: true

# List contents of a database table
# Usage: ruby db/utils/list_table.rb <table_name> [limit]
# Example: ruby db/utils/list_table.rb projects
# Example: ruby db/utils/list_table.rb time_entries 10

require 'logger'

# Initialize logger
$logger = Logger.new($stdout)
$logger.level = Logger::WARN

require_relative '../../config/database'

def list_table(table_name, limit = nil)
  table = table_name.to_sym
  
  unless DB.table_exists?(table)
    puts "❌ Table '#{table_name}' does not exist"
    puts "\nAvailable tables:"
    DB.tables.each { |t| puts "  - #{t}" }
    exit 1
  end

  dataset = DB[table]
  total_count = dataset.count
  
  # Apply limit if specified
  dataset = dataset.limit(limit.to_i) if limit

  puts "Table: #{table_name}"
  puts "Total records: #{total_count}"
  puts "Showing: #{limit ? "first #{limit}" : "all"}"
  puts "=" * 80
  
  if dataset.empty?
    puts "(empty)"
  else
    dataset.each do |record|
      puts "-" * 80
      record.each do |key, value|
        # Format dates and times nicely
        formatted_value = case value
        when Time, DateTime
          value.strftime('%Y-%m-%d %H:%M:%S')
        when Date
          value.to_s
        else
          value.inspect
        end
        puts "  #{key}: #{formatted_value}"
      end
    end
    puts "=" * 80
  end
  
  puts "\nShowing #{dataset.count} of #{total_count} records"
end

# Main
if ARGV.empty?
  puts "Usage: ruby db/utils/list_table.rb <table_name> [limit]"
  puts "\nAvailable tables:"
  DB.tables.each { |t| puts "  - #{t}" }
  exit 1
end

table_name = ARGV[0]
limit = ARGV[1]

list_table(table_name, limit)
