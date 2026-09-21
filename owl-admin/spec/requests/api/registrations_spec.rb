require "rails_helper"

RSpec.describe "Api::Registrations", type: :request do
  it "creates a user and returns a token" do
    expect do
      post api_registrations_path, params: { email: "new@example.com", password: "password123" }, as: :json
    end.to change(User, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["token"]).to be_present
  end

  it "rejects a duplicate email" do
    create(:user, email: "dup2@example.com")

    post api_registrations_path, params: { email: "dup2@example.com", password: "password123" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end
end
