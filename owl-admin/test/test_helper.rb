ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
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
