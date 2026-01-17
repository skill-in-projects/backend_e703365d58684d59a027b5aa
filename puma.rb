# Puma configuration for Railway deployment
# This ensures Puma binds to 0.0.0.0 (all interfaces) instead of localhost
# Railway sets PORT environment variable - use it or default to 8080

bind "tcp://0.0.0.0:#{ENV.fetch('PORT', '8080')}"
workers 0  # Single worker mode for Railway
threads 0, 5
