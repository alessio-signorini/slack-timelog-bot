#!/usr/bin/env ruby
# frozen_string_literal: true

# Delete a record from a database table
# Usage: ruby db/utils/delete_record.rb <table_name> <id> [--force]
# Example: ruby db/utils/delete_record.rb projects 1
# Example: ruby db/utils/delete_record.rb time_entries 5 --force

require 'logger'

# Initialize logger
$logger = Logger.new($stdout)
$logger.level = Logger::WARN

require_relative '../../config/database'

def delete_record(table_name, id, force = false)
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

  puts "Record to delete:"
  puts "-" * 80
  record.each { |k, v| puts "  #{k}: #{v.inspect}" }
  puts "-" * 80
  puts ""
  
  unless force
    print "Are you sure you want to delete this record? (yes/no): "
    confirmation = $stdin.gets.chomp.downcase
    
    unless confirmation == 'yes' || confirmation == 'y'
      puts "❌ Deletion cancelled"
      exit 0
    end
  end
  
  # Delete the record
  deleted_count = dataset.where(id: id).delete
  
  if deleted_count > 0
    puts "✅ Record deleted successfully!"
  else
    puts "❌ Failed to delete record"
    exit 1
  end
end

# Main
if ARGV.empty? || ARGV.length < 2
  puts "Usage: ruby db/utils/delete_record.rb <table_name> <id> [--force]"
  puts ""
  puts "Examples:"
  puts "  ruby db/utils/delete_record.rb projects 1"
  puts "  ruby db/utils/delete_record.rb time_entries 5 --force"
  puts ""
  puts "Options:"
  puts "  --force    Skip confirmation prompt"
  puts ""
  puts "Available tables:"
  DB.tables.each { |t| puts "  - #{t}" }
  exit 1
end

table_name = ARGV[0]
id = ARGV[1].to_i
force = ARGV.include?('--force')

delete_record(table_name, id, force)
