require "rails_helper"

RSpec.describe "Internal::Conversations", type: :request do
  let(:user) { create(:user, email: "student@example.com") }
  let(:conversation) { user.conversations.create!(title: "Becas en Alemania") }
  let(:secret) { "test-internal-secret" }
  let(:auth_headers) { { "Authorization" => "Bearer #{secret}" } }

  around do |example|
    ENV["OWL_INTERNAL_SECRET"] = secret
    example.run
    ENV.delete("OWL_INTERNAL_SECRET")
  end

  before do
    conversation.messages.create!(role: :user, content: "¿Qué becas hay para Alemania?")
    conversation.messages.create!(role: :assistant, content: "Considera DAAD.", agent: "general_advisor",
      citations: [ { "scholarship_id" => "4", "title" => "DAAD", "source_url" => "https://daad.de" } ])
  end

  it "sends the transcript to the conversation's owner" do
    expect do
      post internal_email_conversation_path(conversation), headers: auth_headers
    end.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)).to eq("status" => "sent")

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "student@example.com" ])
    expect(mail.subject).to include("Becas en Alemania")
    expect(mail.html_part.body.to_s).to include("Considera DAAD.")
    expect(mail.html_part.body.to_s).to include("DAAD")
  end

  it "returns 404 for an unknown conversation" do
    post internal_email_conversation_path(id: 0), headers: auth_headers
    expect(response).to have_http_status(:not_found)
  end

  it "requires the shared secret" do
    post internal_email_conversation_path(conversation)
    expect(response).to have_http_status(:unauthorized)
  end
end
