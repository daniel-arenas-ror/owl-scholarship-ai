require "rails_helper"

RSpec.describe "Admin conversations", type: :request do
  include_context "signed in admin"

  let(:student) { create(:user, email: "student@example.com") }
  let(:conversation) { student.conversations.create!(title: "Doctorado en ciencias") }

  before do
    conversation.messages.create!(role: :user, content: "¿becas de doctorado?")
    answer = conversation.messages.create!(
      role: :assistant, content: "Considera MinCiencias.", agent: "scholarship_expert",
      citations: [ { "scholarship_id" => "7", "title" => "MinCiencias", "source_url" => "https://minciencias.gov.co" } ],
      trace_run_id: "run-abc-123"
    )
    answer.create_feedback!(rating: :down, reason: "muy corto")
  end

  it "lists conversations with message counts" do
    get admin_conversations_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Doctorado en ciencias")
  end

  it "shows the full transcript with agent, citation, feedback and trace link" do
    get admin_conversation_path(conversation)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Considera MinCiencias.")
    expect(response.body).to include("experto")
    expect(response.body).to include("MinCiencias")
    expect(response.body).to include(%(href="https://smith.langchain.com/o/-/projects/p/owl-dev/r/run-abc-123"))
    expect(response.body).to include("👎")
  end
end
