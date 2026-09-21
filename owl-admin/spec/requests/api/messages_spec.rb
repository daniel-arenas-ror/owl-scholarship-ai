require "rails_helper"

RSpec.describe "Api::Messages feedback", type: :request do
  let(:user) { create(:user, email: "fb@example.com") }
  let(:conversation) { user.conversations.create! }
  let(:message) { create(:message, :assistant, conversation: conversation) }
  let(:token) { JwtService.encode({ sub: user.id.to_s }, audience: "owl-admin") }
  let(:auth_headers) { { "Authorization" => "Bearer #{token}" } }

  it "records a thumbs-up" do
    post feedback_api_message_path(message), params: { rating: "up" }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:success)
    expect(message.reload.feedback.rating).to eq("up")
  end

  it "records a thumbs-down with a reason" do
    post feedback_api_message_path(message),
      params: { rating: "down", reason: "no aplica a mi caso" }, headers: auth_headers, as: :json

    expect(response).to have_http_status(:success)
    expect(message.reload.feedback.rating).to eq("down")
    expect(message.feedback.reason).to eq("no aplica a mi caso")
  end

  it "updates the same feedback row instead of creating a new one when you change your mind" do
    post feedback_api_message_path(message), params: { rating: "up" }, headers: auth_headers, as: :json
    post feedback_api_message_path(message), params: { rating: "down" }, headers: auth_headers, as: :json

    expect(Feedback.where(message: message).count).to eq(1)
    expect(message.reload.feedback.rating).to eq("down")
  end

  it "rejects an invalid rating" do
    post feedback_api_message_path(message), params: { rating: "sideways" }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "will not accept feedback on another user's message" do
    other = create(:user, email: "other-fb@example.com")
    other_message = create(:message, :assistant, conversation: other.conversations.create!)

    post feedback_api_message_path(other_message), params: { rating: "up" }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "requires auth" do
    post feedback_api_message_path(message), params: { rating: "up" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
