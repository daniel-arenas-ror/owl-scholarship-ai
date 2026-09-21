# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"
# Unconditional, not ||= : the dev container image sets RAILS_ENV=development
# (Dockerfile.dev), and `bin/rails test` only works around that itself by also
# assigning unconditionally (see railties' test_unit/runner.rb). Without this,
# specs boot in development — the dev database, and development.rb's
# `config.hosts << "admin"`, which 403s every request spec (RSpec's default
# host is www.example.com, not "admin").
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "factory_bot_rails"
require "shoulda/matchers"

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# owl-admin reads owl-api's `scholarships` table over a second connection that
# Rails doesn't manage (database_tasks: false). Make sure the table exists in
# the test DB — created here, not by a migration.
OwlApiRecord.connection.execute(File.read(Rails.root.join("spec/support/owl_api_schema.sql")))

# Support files: shared contexts, custom helpers (spec/support/**/*.rb).
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request

  # Match db/seeds.rb: AI_SCHOLARSHIP_AGENT defaults on ("current behavior").
  # A spec that cares about the disabled path flips it explicitly.
  config.before { Flipper.enable(Features::AI_SCHOLARSHIP_AGENT) }
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
