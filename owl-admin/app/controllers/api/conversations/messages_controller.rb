# Streams one conversational turn. The browser makes a single request here;
# owl-admin persists the user message, relays owl-api's SSE stream token by
# token, then persists the assembled answer and closes with a final event.
# owl-api only ever sees owl-admin.
class Api::Conversations::MessagesController < Api::BaseController
  include ActionController::Live

  def create
    conversation = current_user.conversations.find_by(id: params[:conversation_id])
    return render(json: { error: "not found" }, status: :not_found) unless conversation

    user_message = conversation.messages.create!(role: :user, content: params[:content])
    start_event_stream
    sse("user_message", user_message.as_json_public)

    assembled = +""
    citations = []
    agent = "general_advisor"
    errored = false

    OwlApiClient.stream(conversation: conversation, user_message: user_message) do |event, data|
      case event
      when "token"
        assembled << data["content"].to_s
        sse("token", data)
      when "error"
        errored = true
        sse("error", data)
      when "done"
        citations = data["citations"] || []
        agent = data["agent"].presence || agent
        assembled = data["message"] if data["message"].present?
      end
    end

    return if errored

    assistant_message = conversation.messages.create!(
      role: :assistant, content: assembled, agent: agent, citations: citations
    )
    sse("done", assistant_message.as_json_public)
  rescue OwlApiClient::Error => e
    sse("error", { detail: e.message })
  ensure
    response.stream.close if @streaming
  end

  private

  def start_event_stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    # Defeats Rack::ETag, which would otherwise buffer the whole response.
    response.headers["Last-Modified"] = Time.now.httpdate
    @streaming = true
  end

  def sse(event, data)
    response.stream.write("event: #{event}\ndata: #{data.to_json}\n\n")
  rescue IOError, ActionController::Live::ClientDisconnected
    # the browser hung up mid-stream; nothing left to send
  end
end
