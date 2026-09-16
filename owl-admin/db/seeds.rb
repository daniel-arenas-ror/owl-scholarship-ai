# Idempotent seed data for local development.
#
#   bin/rails db:seed
#   (or: make console -> load "#{Rails.root}/db/seeds.rb")

admin = User.find_or_initialize_by(email: "admin@example.com")
if admin.new_record?
  admin.password = ENV.fetch("ADMIN_PASSWORD", "password123")
  admin.role = :admin
  admin.save!
  puts "created admin user admin@example.com"
else
  admin.update!(role: :admin)
  puts "admin@example.com already exists"
end

student = User.find_or_initialize_by(email: "maria@example.com")
if student.new_record?
  student.password = "password123"
  student.role = :student
  student.save!
  puts "created student user maria@example.com"
end

# Default every feature flag on, matching current behavior, until an admin
# decides otherwise at /admin/flipper. Flipper.enable is idempotent.
Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
puts "ai_scholarship_agent: #{Features.ai_scholarship_agent? ? 'on' : 'off'}"
