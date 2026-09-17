require "test_helper"

class Internal::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "student@example.com", password: "password123")
    @secret = "test-internal-secret"
    ENV["OWL_INTERNAL_SECRET"] = @secret
  end

  teardown { ENV.delete("OWL_INTERNAL_SECRET") }

  test "show_profile returns the profile fields" do
    @user.update!(full_name: "Maria Lopez", phone: "3001234567", degrees: [ "Ingeniería" ])

    get internal_user_profile_path(@user), headers: auth_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "Maria Lopez", body["full_name"]
    assert_equal "student@example.com", body["email"]
    assert_equal [ "Ingeniería" ], body["degrees"]
  end

  test "update_profile sets only full_name, phone, and degrees" do
    patch internal_update_user_profile_path(@user),
      params: { full_name: "Maria Lopez", degrees: [ "Ingeniería", "MBA" ] }.to_json,
      headers: auth_headers.merge("Content-Type" => "application/json")

    assert_response :success
    @user.reload
    assert_equal "Maria Lopez", @user.full_name
    assert_equal %w[Ingeniería MBA], @user.degrees
    assert_nil @user.phone # untouched — not sent this time
  end

  test "update_profile cannot touch email, role, or password" do
    patch internal_update_user_profile_path(@user),
      params: { email: "hijacked@example.com", role: "admin" }.to_json,
      headers: auth_headers.merge("Content-Type" => "application/json")

    assert_response :success
    @user.reload
    assert_equal "student@example.com", @user.email
    assert_equal "student", @user.role
  end

  test "requires the shared secret" do
    get internal_user_profile_path(@user)
    assert_response :unauthorized

    get internal_user_profile_path(@user), headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
  end

  test "refuses when no secret is configured" do
    ENV.delete("OWL_INTERNAL_SECRET")
    get internal_user_profile_path(@user), headers: auth_headers
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@secret}" }
  end
end
