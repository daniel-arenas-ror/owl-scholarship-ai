require "rails_helper"

RSpec.describe "Api::Conversations", type: :request do
  let(:user) { create(:user, email: "convo@example.com") }
  let(:token) { JwtService.encode({ sub: user.id.to_s }, audience: "owl-admin") }
  let(:auth_headers) { { "Authorization" => "Bearer #{token}" } }

  it "creates a conversation for the current user" do
    post api_conversations_path, headers: auth_headers
    expect(response).to have_http_status(:created)
    expect(user.conversations.count).to eq(1)
  end

  it "shows a conversation with its messages" do
    conversation = user.conversations.create!
    conversation.messages.create!(role: :user, content: "hola")

    get api_conversation_path(conversation), headers: auth_headers
    expect(response).to have_http_status(:success)

    body = JSON.parse(response.body)
    expect(body["messages"].length).to eq(1)
  end

  it "will not show another user's conversation" do
    other = create(:user, email: "other@example.com")
    conversation = other.conversations.create!

    get api_conversation_path(conversation), headers: auth_headers
    expect(response).to have_http_status(:not_found)
  end

  it "requires auth" do
    post api_conversations_path
    expect(response).to have_http_status(:unauthorized)
  end
end
