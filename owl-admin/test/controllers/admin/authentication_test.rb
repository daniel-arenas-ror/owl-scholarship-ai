require "test_helper"

class Admin::AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "admin@example.com", password: "password123", role: :admin)
    @student = User.create!(email: "student@example.com", password: "password123", role: :student)
  end

  test "admin routes redirect to login when signed out" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "a valid admin can sign in and reach the panel" do
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_select "h1", "Panel"
  end

  test "a student is refused at the login form" do
    post user_session_path, params: { user: { email: @student.email, password: "password123" } }
    assert_response :unprocessable_entity
    assert_match(/administrador/, response.body)

    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "wrong password is rejected" do
    post user_session_path, params: { user: { email: @admin.email, password: "nope" } }
    assert_response :unprocessable_entity
  end

  test "signed-in admin can sign out" do
    sign_in @admin
    delete destroy_user_session_path
    assert_redirected_to new_user_session_path
    get admin_root_path
    assert_redirected_to new_user_session_path
  end
end
