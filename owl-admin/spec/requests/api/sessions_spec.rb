require "rails_helper"

RSpec.describe "Api::Sessions", type: :request do
  let(:user) { create(:user, email: "login@example.com") }

  it "logs in with the right password" do
    post api_session_path, params: { email: user.email, password: "password123" }, as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["token"]).to be_present
    expect(body["user"]["email"]).to eq(user.email)
  end

  it "rejects the wrong password" do
    post api_session_path, params: { email: user.email, password: "nope" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
