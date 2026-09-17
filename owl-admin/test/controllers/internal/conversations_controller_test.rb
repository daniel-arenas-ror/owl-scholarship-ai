require "test_helper"

class Internal::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "student@example.com", password: "password123")
    @conversation = @user.conversations.create!(title: "Becas en Alemania")
    @conversation.messages.create!(role: :user, content: "¿Qué becas hay para Alemania?")
    @conversation.messages.create!(role: :assistant, content: "Considera DAAD.", agent: "general_advisor",
      citations: [ { "scholarship_id" => "4", "title" => "DAAD", "source_url" => "https://daad.de" } ])

    @secret = "test-internal-secret"
    ENV["OWL_INTERNAL_SECRET"] = @secret
  end

  teardown { ENV.delete("OWL_INTERNAL_SECRET") }

  test "sends the transcript to the conversation's owner" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post internal_email_conversation_path(@conversation), headers: auth_headers
    end

    assert_response :success
    assert_equal({ "status" => "sent" }, JSON.parse(response.body))

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "student@example.com" ], mail.to
    assert_match "Becas en Alemania", mail.subject
    assert_match "Considera DAAD.", mail.html_part.body.to_s
    assert_match "DAAD", mail.html_part.body.to_s
  end

  test "unknown conversation is a 404" do
    post internal_email_conversation_path(id: 0), headers: auth_headers
    assert_response :not_found
  end

  test "requires the shared secret" do
    post internal_email_conversation_path(@conversation)
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@secret}" }
  end
end
