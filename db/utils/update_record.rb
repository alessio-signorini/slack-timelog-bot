#!/usr/bin/env ruby
# frozen_string_literal: true

# Update a record in a database table
# Usage: ruby db/utils/update_record.rb <table_name> <id> key=value [key=value ...]
# Example: ruby db/utils/update_record.rb projects 1 name="New Project"
# Example: ruby db/utils/update_record.rb time_entries 5 minutes=120 notes="Updated notes"

require 'logger'
require 'date'

# Initialize logger
$logger = Logger.new($stdout)
$logger.level = Logger::WARN

require_relative '../../config/database'

def parse_value(value_str)
  # Try to intelligently parse the value
  return nil if value_str == 'null' || value_str == 'NULL'
  return true if value_str == 'true'
  return false if value_str == 'false'
  
  # Try integer
  return value_str.to_i if value_str.match?(/^\d+$/)
  
  # Try float
  return value_str.to_f if value_str.match?(/^\d+\.\d+$/)
  
  # Try date (YYYY-MM-DD)
  if value_str.match?(/^\d{4}-\d{2}-\d{2}$/)
    begin
      return Date.parse(value_str)
    rescue ArgumentError
      # Not a valid date, treat as string
    end
  end
  
  # Default to string (remove surrounding quotes if present)
  value_str.gsub(/^["']|["']$/, '')
end

def update_record(table_name, id, updates)
  table = table_name.to_sym
  
  unless DB.table_exists?(table)
    puts "❌ Table '#{table_name}' does not exist"
    puts "\nAvailable tables:"
    DB.tables.each { |t| puts "  - #{t}" }
    exit 1
  end

  dataset = DB[table]
  record = dataset.where(id: id).first
  
  unless record
    puts "❌ Record with id=#{id} not found in table '#{table_name}'"
    exit 1
  end

  puts "Current record:"
  puts "-" * 80
  record.each { |k, v| puts "  #{k}: #{v.inspect}" }
  puts "-" * 80
  puts ""
  
  # Parse updates
  parsed_updates = {}
  updates.each do |update_str|
    unless update_str.include?('=')
      puts "⚠️  Skipping invalid update: #{update_str} (must be key=value)"
      next
    end
    
    key, value = update_str.split('=', 2)
    key = key.strip.to_sym
    
    unless record.key?(key)
      puts "⚠️  Skipping unknown column: #{key}"
      next
    end
    
    parsed_updates[key] = parse_value(value.strip)
  end
  
  if parsed_updates.empty?
    puts "❌ No valid updates to apply"
    exit 1
  end
  
  puts "Applying updates:"
  parsed_updates.each { |k, v| puts "  #{k}: #{v.inspect}" }
  puts ""
  
  # Update the record
  dataset.where(id: id).update(parsed_updates)
  
  # Show updated record
  updated_record = dataset.where(id: id).first
  puts "✅ Record updated successfully!"
  puts "-" * 80
  updated_record.each { |k, v| puts "  #{k}: #{v.inspect}" }
  puts "-" * 80
end

# Main
if ARGV.length < 3
  puts "Usage: ruby db/utils/update_record.rb <table_name> <id> key=value [key=value ...]"
  puts ""
  puts "Examples:"
  puts "  ruby db/utils/update_record.rb projects 1 name=\"New Project\""
  puts "  ruby db/utils/update_record.rb time_entries 5 minutes=120 notes=\"Updated\""
  puts "  ruby db/utils/update_record.rb users 2 timezone=\"America/New_York\""
  puts ""
  puts "Available tables:"
  DB.tables.each { |t| puts "  - #{t}" }
  exit 1
end

table_name = ARGV[0]
id = ARGV[1].to_i
updates = ARGV[2..-1]

update_record(table_name, id, updates)
