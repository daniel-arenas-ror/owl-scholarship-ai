ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# owl-admin reads owl-api's `scholarships` table over a second connection that
# Rails doesn't manage (database_tasks: false). Make sure the table exists in
# the test DB — created here, not by a migration.
OwlApiRecord.connection.execute(File.read(Rails.root.join("test/support/owl_api_schema.sql")))

module ActiveSupport
  class TestCase
    # Single process: the `owl_api` connection (owl-api's DB, read directly) has
    # no per-worker copy, so parallel workers would fight over it. The suite is
    # small enough that serial is fine.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Match db/seeds.rb: AI_SCHOLARSHIP_AGENT defaults on ("current behavior").
    # A test that cares about the disabled path flips it explicitly.
    setup { Flipper.enable(Features::AI_SCHOLARSHIP_AGENT) }

    # owl-api's `scholarships` table is shared across parallel workers (no
    # per-worker copy), so each test cleans up exactly the rows it made.
    teardown do
      Scholarship.where(id: @_created_scholarships).delete_all if @_created_scholarships.present?
    end

    # Build a Scholarship fixture in owl-api's table with sane defaults.
    def create_scholarship(**attrs)
      record = Scholarship.create!({
        source: "example.com",
        source_url: "https://example.com/#{SecureRandom.hex(6)}",
        title: "Beca de prueba",
        provider: "Proveedor de prueba",
        country: "CO",
        fields: [],
        levels: [ "maestría" ],
        body_markdown: "Cuerpo de la beca con suficiente texto de relleno.",
        content_hash: SecureRandom.hex(16)
      }.merge(attrs))
      (@_created_scholarships ||= []) << record.id
      record
    end
  end
end

class ActionDispatch::IntegrationTest
  # Devise's `sign_in` / `sign_out` for controller/integration tests.
  include Devise::Test::IntegrationHelpers
end

# Mix into an admin controller test to get a signed-in `@admin`.
module SignedInAdmin
  extend ActiveSupport::Concern

  included do
    setup do
      @admin = User.create!(email: "admin-#{SecureRandom.hex(4)}@example.com",
                            password: "password123", role: :admin)
      sign_in @admin
    end
  end
end
