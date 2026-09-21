require "rails_helper"

RSpec.describe "Api::Conversations::Messages", type: :request do
  let(:user) { create(:user, email: "chat@example.com") }
  let(:conversation) { user.conversations.create! }
  let(:token) { JwtService.encode({ sub: user.id.to_s }, audience: "owl-admin") }
  let(:auth_headers) { { "Authorization" => "Bearer #{token}" } }

  def stub_owl_api_stream(events)
    allow(OwlApiClient).to receive(:stream) do |conversation:, user_message:, &block|
      events.each { |event, data| block.call(event, data) }
    end
  end

  it "streams the relayed answer and persists both messages" do
    stub_owl_api_stream([
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
    ])

    post api_conversation_messages_path(conversation),
      params: { content: "beca para el Reino Unido" }, headers: auth_headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/event-stream")
    expect(response.body).to include("event: user_message")
    expect(response.body).to include(%(event: routing\ndata: {"route":"expert"))
    expect(response.body).to include(%(event: token\ndata: {"content":"Puedes "}))
    expect(response.body).to include("event: done")

    expect(conversation.messages.count).to eq(2)
    assistant = conversation.messages.find_by(role: :assistant)
    expect(assistant.content).to eq("Puedes considerar Chevening.")
    expect(assistant.agent).to eq("scholarship_expert")
    expect(assistant.citations.length).to eq(1)
    expect(assistant.trace_run_id).to eq("run-xyz-789")
    expect(assistant.system_prompt).to eq("Eres Owl … FICHA: Chevening …")
    expect(assistant.model_variant).to eq("base")
  end

  it "relays an error event from owl-api without 500ing" do
    stub_owl_api_stream([ [ "error", { "detail" => "kaboom" } ] ])

    post api_conversation_messages_path(conversation),
      params: { content: "hola" }, headers: auth_headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(event: error\ndata: {"detail":"kaboom"}))
    expect(response.body).not_to include("event: done")
    # user message saved; no assistant message persisted for a failed turn
    expect(conversation.messages.pluck(:role)).to eq([ "user" ])
  end

  it "requires auth" do
    post api_conversation_messages_path(conversation), params: { content: "hola" }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 404 for an unknown conversation without opening a stream" do
    other = create(:user, email: "other@example.com")
    stranger_conversation = other.conversations.create!

    post api_conversation_messages_path(stranger_conversation),
      params: { content: "hola" }, headers: auth_headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
  end

  it "refuses to call owl-api when AI_SCHOLARSHIP_AGENT is disabled" do
    Flipper.disable(Features::AI_SCHOLARSHIP_AGENT)
    stub_owl_api_stream([])

    post api_conversation_messages_path(conversation),
      params: { content: "hola" }, headers: auth_headers, as: :json

    expect(response).to have_http_status(:service_unavailable)
    expect(response.media_type).to eq("application/json")
    expect(conversation.messages.count).to eq(0)
  ensure
    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
  end
end
