class ApplicationMailer < ActionMailer::Base
  # ENV["OWL_MAILER_FROM"], not .fetch — docker-compose always defines the key
  # (blank passthrough), so .fetch's fallback would never actually trigger.
  default from: ENV["OWL_MAILER_FROM"].presence || "Owl <owl@example.com>"
  layout "mailer"
end
