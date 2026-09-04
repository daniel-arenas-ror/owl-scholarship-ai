require "net/http"
require "json"

# Calls owl-api's agent endpoint on behalf of a conversation turn, authorizing
# with a short-lived service JWT (aud: "owl-api").
class OwlApiClient
  class Error < StandardError; end

  TIMEOUT_SECONDS = 20

  def self.respond(conversation:, user_message:, user_context: {})
    new.respond(conversation: conversation, user_message: user_message, user_context: user_context)
  end

  def respond(conversation:, user_message:, user_context: {})
    uri = URI.join(base_url, "/v1/agent/respond")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{service_token(conversation)}"
    request["Content-Type"] = "application/json"
    request.body = {
      conversation_id: conversation.id.to_s,
      thread_id: conversation.id.to_s,
      user_message: user_message.content,
      history: history_for(conversation, excluding: user_message),
      user_context: user_context
    }.to_json

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
    ) { |http| http.request(request) }

    raise Error, "owl-api returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  rescue StandardError => e
    raise e if e.is_a?(Error)

    raise Error, e.message
  end

  private

  def service_token(conversation)
    JwtService.encode({ sub: conversation.user_id.to_s }, audience: "owl-api", expires_in: 5.minutes)
  end

  def history_for(conversation, excluding:)
    conversation.messages.where.not(id: excluding.id).order(:created_at).map do |m|
      { role: m.role, content: m.content }
    end
  end

  def base_url
    ENV.fetch("OWL_API_URL", "http://localhost:8000")
  end
end
