require "test_helper"

class Api::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "creates a user and returns a token" do
    assert_difference "User.count", 1 do
      post api_registrations_path, params: { email: "new@example.com", password: "password123" }, as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body["token"].present?
  end

  test "rejects a duplicate email" do
    User.create!(email: "dup2@example.com", password: "password123")

    post api_registrations_path, params: { email: "dup2@example.com", password: "password123" }, as: :json
    assert_response :unprocessable_entity
  end
end
