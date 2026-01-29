#!/usr/bin/env ruby
# frozen_string_literal: true

# Clean up duplicate time entries
# Keeps the first entry and deletes subsequent duplicates
# Duplicates are identified by: user_id, project_id, minutes, date, notes, original_message

require 'logger'
$logger = Logger.new($stdout)
$logger.level = Logger::INFO

require_relative '../../config/environment'

puts "Finding duplicate time entries..."

# Group entries by unique key fields
duplicates = DB[:time_entries]
  .select(:user_id, :project_id, :minutes, :date, :notes, :original_message)
  .select_append { count(:id).as(:count) }
  .select_append { min(:id).as(:first_id) }
  .group(:user_id, :project_id, :minutes, :date, :notes, :original_message)
  .having { count(:id) > 1 }
  .all

if duplicates.empty?
  puts "No duplicates found!"
  exit 0
end

puts "Found #{duplicates.length} groups of duplicates"

total_deleted = 0

duplicates.each do |dup|
  # Get all IDs for this duplicate group
  ids = DB[:time_entries]
    .where(
      user_id: dup[:user_id],
      project_id: dup[:project_id],
      minutes: dup[:minutes],
      date: dup[:date],
      notes: dup[:notes],
      original_message: dup[:original_message]
    )
    .select(:id)
    .map { |r| r[:id] }
  
  # Keep the first (lowest ID), delete the rest
  keep_id = ids.min
  delete_ids = ids - [keep_id]
  
  puts "Keeping entry #{keep_id}, deleting #{delete_ids.length} duplicates: #{delete_ids.join(', ')}"
  
  delete_ids.each do |id|
    DB[:time_entries].where(id: id).delete
    total_deleted += 1
  end
end

puts "\nCleanup complete! Deleted #{total_deleted} duplicate entries."
