require "net/http"
require "json"

# Calls owl-api on behalf of owl-admin, authorizing every request with a
# short-lived service JWT (aud: "owl-api"). Used for conversation turns now;
# the Phase 3 scraper will reuse .ingest to push scraped scholarships.
class OwlApiClient
  class Error < StandardError; end

  TIMEOUT_SECONDS = 20

  def self.respond(conversation:, user_message:, user_context: {})
    new.respond(conversation: conversation, user_message: user_message, user_context: user_context)
  end

  def self.ingest(scholarship)
    new.ingest(scholarship)
  end

  def respond(conversation:, user_message:, user_context: {})
    post_json(
      "/v1/agent/respond",
      {
        conversation_id: conversation.id.to_s,
        thread_id: conversation.id.to_s,
        user_message: user_message.content,
        history: history_for(conversation, excluding: user_message),
        user_context: user_context
      },
      sub: conversation.user_id.to_s
    )
  end

  def ingest(scholarship)
    post_json("/v1/scholarships/ingest", scholarship, sub: "owl-admin")
  end

  private

  def post_json(path, payload, sub:)
    uri = URI.join(base_url, path)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{service_token(sub)}"
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS
    ) { |http| http.request(request) }

    raise Error, "owl-api returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  rescue StandardError => e
    raise e if e.is_a?(Error)

    raise Error, e.message
  end

  def service_token(sub)
    JwtService.encode({ sub: sub }, audience: "owl-api", expires_in: 5.minutes)
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
