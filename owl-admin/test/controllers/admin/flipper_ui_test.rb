require "test_helper"

# Flipper::UI is a mounted Rack app, not an Admin::BaseController subclass, so
# it can't run a before_action — routes.rb gates it with a request constraint
# instead. These tests prove that gate actually holds.
class Admin::FlipperUiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "admin@example.com", password: "password123", role: :admin)
    @student = User.create!(email: "student@example.com", password: "password123", role: :student)
    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
  end

  test "an admin can reach the flag management UI" do
    sign_in @admin
    get "/admin/flipper"
    assert_redirected_to "/admin/flipper/features" # Flipper::UI's own root redirect
    follow_redirect!
    assert_response :success
    assert_match "ai_scholarship_agent", response.body
  end

  test "a signed-out visitor is redirected to login" do
    get "/admin/flipper"
    assert_redirected_to new_user_session_path
  end

  test "a signed-in non-admin is redirected to login too" do
    sign_in @student
    get "/admin/flipper"
    assert_redirected_to new_user_session_path
  end
end
