require "test_helper"

class Admin::ConversationsControllerTest < ActionDispatch::IntegrationTest
  include SignedInAdmin

  setup do
    @student = User.create!(email: "student@example.com", password: "password123")
    @conversation = @student.conversations.create!(title: "Doctorado en ciencias")
    @conversation.messages.create!(role: :user, content: "¿becas de doctorado?")
    @answer = @conversation.messages.create!(
      role: :assistant, content: "Considera MinCiencias.", agent: "scholarship_expert",
      citations: [ { "scholarship_id" => "7", "title" => "MinCiencias", "source_url" => "https://minciencias.gov.co" } ],
      trace_run_id: "run-abc-123"
    )
    @answer.create_feedback!(rating: :down, reason: "muy corto")
  end

  test "index lists conversations with message counts" do
    get admin_conversations_path
    assert_response :success
    assert_match "Doctorado en ciencias", response.body
  end

  test "show renders the full transcript with agent, citation, feedback and trace link" do
    get admin_conversation_path(@conversation)

    assert_response :success
    assert_match "Considera MinCiencias.", response.body
    assert_match "experto", response.body
    assert_match "MinCiencias", response.body
    assert_select "a[href=?]", "https://smith.langchain.com/o/-/projects/p/owl-dev/r/run-abc-123"
    assert_match "👎", response.body
  end
end
