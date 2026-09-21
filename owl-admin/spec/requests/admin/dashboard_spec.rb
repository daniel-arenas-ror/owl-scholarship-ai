require "rails_helper"

RSpec.describe "Admin dashboard", type: :request do
  include_context "signed in admin"

  it "renders the panel with headline counts" do
    student = create(:user, email: "s@example.com")
    conversation = student.conversations.create!(title: "Beca en Alemania")
    conversation.messages.create!(role: :user, content: "hola")
    assistant = conversation.messages.create!(role: :assistant, content: "respuesta", agent: "general_advisor")
    assistant.create_feedback!(rating: :up)

    get admin_root_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Panel")
    expect(response.body).to include("Beca en Alemania")
    expect(response.body).to include("100%") # 1 up / 0 down
  end
end
