require "test_helper"

class Api::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "login@example.com", password: "password123")
  end

  test "logs in with the right password" do
    post api_session_path, params: { email: @user.email, password: "password123" }, as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert body["token"].present?
    assert_equal @user.email, body["user"]["email"]
  end

  test "rejects the wrong password" do
    post api_session_path, params: { email: @user.email, password: "nope" }, as: :json
    assert_response :unauthorized
  end
end
