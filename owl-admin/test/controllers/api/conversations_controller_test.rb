require "test_helper"

class Api::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "convo@example.com", password: "password123")
    @token = JwtService.encode({ sub: @user.id.to_s }, audience: "owl-admin")
  end

  test "creates a conversation for the current user" do
    post api_conversations_path, headers: auth_headers
    assert_response :created
    assert_equal 1, @user.conversations.count
  end

  test "shows a conversation with its messages" do
    conversation = @user.conversations.create!
    conversation.messages.create!(role: :user, content: "hola")

    get api_conversation_path(conversation), headers: auth_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["messages"].length
  end

  test "will not show another user's conversation" do
    other = User.create!(email: "other@example.com", password: "password123")
    conversation = other.conversations.create!

    get api_conversation_path(conversation), headers: auth_headers
    assert_response :not_found
  end

  test "requires auth" do
    post api_conversations_path
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end
end
