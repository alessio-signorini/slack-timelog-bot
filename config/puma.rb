# frozen_string_literal: true

# Puma configuration for production

# Workers based on available memory (Fly.io typically has limited memory)
workers ENV.fetch('WEB_CONCURRENCY', 2).to_i

# Threads per worker
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5).to_i
threads threads_count, threads_count

# Bind to port
port ENV.fetch('PORT', 8080)

# Environment
environment ENV.fetch('RACK_ENV', 'production')

# Preload for copy-on-write memory savings
preload_app!

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

on_worker_boot do
  # Reconnect to database on worker boot
  TimelogBot::Database.disconnect
  TimelogBot::Database.establish_connection
end

before_fork do
  # Disconnect before forking
  TimelogBot::Database.disconnect
end

# Logging
stdout_redirect(
  ENV.fetch('PUMA_STDOUT', '/dev/stdout'),
  ENV.fetch('PUMA_STDERR', '/dev/stderr'),
  true # append mode
)

lowlevel_error_handler do |e|
  [500, {}, ["Internal Server Error: #{e.message}\n"]]
end
