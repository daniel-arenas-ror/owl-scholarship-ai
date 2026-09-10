require "test_helper"

class Api::Conversations::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "chat@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @token = JwtService.encode({ sub: @user.id.to_s }, audience: "owl-admin")
  end

  test "streams the relayed answer and persists both messages" do
    events = [
      [ "routing", { "route" => "expert", "scholarship_id" => "3", "scholarship_title" => "Chevening" } ],
      [ "token", { "content" => "Puedes " } ],
      [ "token", { "content" => "considerar Chevening." } ],
      [ "done", {
        "message" => "Puedes considerar Chevening.",
        "citations" => [ { "scholarship_id" => "3", "title" => "Chevening", "source_url" => "https://chevening.org" } ],
        "agent" => "scholarship_expert",
        "run_id" => "run-xyz-789",
        "system_prompt" => "Eres Owl … FICHA: Chevening …",
        "model_variant" => "base"
      } ]
    ]

    with_owl_api_stub(events) do
      post api_conversation_messages_path(@conversation),
        params: { content: "beca para el Reino Unido" }, headers: auth_headers, as: :json
    end

    assert_response :ok
    assert_equal "text/event-stream", response.media_type
    assert_includes response.body, "event: user_message"
    assert_includes response.body, %(event: routing\ndata: {"route":"expert")
    assert_includes response.body, %(event: token\ndata: {"content":"Puedes "})
    assert_includes response.body, "event: done"

    assert_equal 2, @conversation.messages.count
    assistant = @conversation.messages.find_by(role: :assistant)
    assert_equal "Puedes considerar Chevening.", assistant.content
    assert_equal "scholarship_expert", assistant.agent
    assert_equal 1, assistant.citations.length
    assert_equal "run-xyz-789", assistant.trace_run_id
    assert_equal "Eres Owl … FICHA: Chevening …", assistant.system_prompt
    assert_equal "base", assistant.model_variant
  end

  test "relays an error event from owl-api without 500ing" do
    with_owl_api_stub([ [ "error", { "detail" => "kaboom" } ] ]) do
      post api_conversation_messages_path(@conversation),
        params: { content: "hola" }, headers: auth_headers, as: :json
    end

    assert_response :ok
    assert_includes response.body, %(event: error\ndata: {"detail":"kaboom"})
    refute_includes response.body, "event: done"
    # user message saved; no assistant message persisted for a failed turn
    assert_equal [ "user" ], @conversation.messages.pluck(:role)
  end

  test "requires auth" do
    post api_conversation_messages_path(@conversation), params: { content: "hola" }, as: :json
    assert_response :unauthorized
  end

  test "unknown conversation returns 404 without opening a stream" do
    other = User.create!(email: "other@example.com", password: "password123")
    stranger_conversation = other.conversations.create!

    post api_conversation_messages_path(stranger_conversation),
      params: { content: "hola" }, headers: auth_headers, as: :json

    assert_response :not_found
    assert_equal "application/json", response.media_type
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def with_owl_api_stub(events)
    original = OwlApiClient.method(:stream)
    OwlApiClient.define_singleton_method(:stream) do |conversation:, user_message:, &block|
      events.each { |event, data| block.call(event, data) }
    end
    yield
  ensure
    OwlApiClient.define_singleton_method(:stream, original)
  end
end
