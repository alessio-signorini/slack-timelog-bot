# frozen_string_literal: true

# Initial projects for the time tracking system
INITIAL_PROJECTS = [
  'Monkey',
  'Barometer',
  'Mushroom',
  'Ferrero Nutella',
  'Consumer',
  'Awesome',
  'ANA'
].freeze

$logger.info('Seeding projects...')

INITIAL_PROJECTS.each do |name|
  begin
    TimelogBot::Models::Project.find_or_create(name: name)
    $logger.info("  Created project: #{name}")
  rescue Sequel::UniqueConstraintViolation
    $logger.info("  Project already exists: #{name}")
  end
end

$logger.info("Seeding complete. #{TimelogBot::Models::Project.count} projects in database.")
