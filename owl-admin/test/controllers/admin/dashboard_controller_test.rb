require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  include SignedInAdmin

  test "renders the panel with headline counts" do
    student = User.create!(email: "s@example.com", password: "password123")
    conversation = student.conversations.create!(title: "Beca en Alemania")
    conversation.messages.create!(role: :user, content: "hola")
    assistant = conversation.messages.create!(role: :assistant, content: "respuesta", agent: "general_advisor")
    assistant.create_feedback!(rating: :up)

    get admin_root_path

    assert_response :success
    assert_select "h1", "Panel"
    assert_match "Beca en Alemania", response.body
    assert_match "100%", response.body # 1 up / 0 down
  end
end
