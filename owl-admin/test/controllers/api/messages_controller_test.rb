require "test_helper"

class Api::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "fb@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @message = @conversation.messages.create!(role: :assistant, content: "respuesta")
    @token = JwtService.encode({ sub: @user.id.to_s }, audience: "owl-admin")
  end

  test "records a thumbs-up" do
    post feedback_api_message_path(@message), params: { rating: "up" }, headers: auth_headers, as: :json
    assert_response :success
    assert_equal "up", @message.reload.feedback.rating
  end

  test "records a thumbs-down with a reason" do
    post feedback_api_message_path(@message),
      params: { rating: "down", reason: "no aplica a mi caso" }, headers: auth_headers, as: :json

    assert_response :success
    assert_equal "down", @message.reload.feedback.rating
    assert_equal "no aplica a mi caso", @message.feedback.reason
  end

  test "changing your mind updates the same feedback row instead of creating a new one" do
    post feedback_api_message_path(@message), params: { rating: "up" }, headers: auth_headers, as: :json
    post feedback_api_message_path(@message), params: { rating: "down" }, headers: auth_headers, as: :json

    assert_equal 1, Feedback.where(message: @message).count
    assert_equal "down", @message.reload.feedback.rating
  end

  test "rejects an invalid rating" do
    post feedback_api_message_path(@message), params: { rating: "sideways" }, headers: auth_headers, as: :json
    assert_response :unprocessable_entity
  end

  test "will not accept feedback on another user's message" do
    other = User.create!(email: "other-fb@example.com", password: "password123")
    other_message = other.conversations.create!.messages.create!(role: :assistant, content: "x")

    post feedback_api_message_path(other_message), params: { rating: "up" }, headers: auth_headers, as: :json
    assert_response :not_found
  end

  test "requires auth" do
    post feedback_api_message_path(@message), params: { rating: "up" }, as: :json
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end
end
