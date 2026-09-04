require "test_helper"

class Api::Conversations::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "chat@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @token = JwtService.encode({ sub: @user.id.to_s }, audience: "owl-admin")
  end

  test "creates a user message and the assistant reply from owl-api" do
    fake_result = { message: "Hola, aquí tienes info.", agent: "general_advisor", citations: [] }
    with_owl_api_client_stubbed(fake_result) do
      post api_conversation_messages_path(@conversation),
        params: { content: "hola" },
        headers: { "Authorization" => "Bearer #{@token}" },
        as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "hola", body["user_message"]["content"]
    assert_equal "Hola, aquí tienes info.", body["assistant_message"]["content"]
    assert_equal 2, @conversation.messages.count
  end

  test "requires auth" do
    post api_conversation_messages_path(@conversation), params: { content: "hola" }, as: :json
    assert_response :unauthorized
  end

  private

  # Swaps OwlApiClient.respond for the duration of the block, so this request
  # test never makes a real HTTP call to owl-api.
  def with_owl_api_client_stubbed(fake_result)
    original = OwlApiClient.method(:respond)
    OwlApiClient.define_singleton_method(:respond) { |**_kwargs| fake_result }
    yield
  ensure
    OwlApiClient.define_singleton_method(:respond, original)
  end
end
