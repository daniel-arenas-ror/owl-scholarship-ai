require "net/http"
require "json"

# Calls owl-api on behalf of owl-admin, authorizing with a short-lived
# service JWT (aud: "owl-api"). owl-admin is owl-api's only client — the
# browser never talks to owl-api directly.
class OwlApiClient
  class Error < StandardError; end

  OPEN_TIMEOUT_SECONDS = 10
  READ_TIMEOUT_SECONDS = 30
  STREAM_READ_TIMEOUT_SECONDS = 120

  def self.ingest(scholarship)
    new.ingest(scholarship)
  end

  def self.stream(conversation:, user_message:, &block)
    new.stream(conversation: conversation, user_message: user_message, &block)
  end

  def ingest(scholarship)
    post_json("/v1/scholarships/ingest", scholarship, sub: "owl-admin")
  end

  # Streams POST /v1/agent/respond, yielding [event, data_hash] for each SSE
  # frame as it arrives. Raises OwlApiClient::Error on a non-2xx or a transport
  # failure.
  def stream(conversation:, user_message:)
    uri = URI.join(base_url, "/v1/agent/respond")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{service_token("owl-admin")}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "text/event-stream"
    request.body = {
      conversation_id: conversation.id.to_s,
      thread_id: conversation.id.to_s,
      user_message: user_message.content
    }.to_json

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT_SECONDS
    http.read_timeout = STREAM_READ_TIMEOUT_SECONDS

    http.start do
      http.request(request) do |response|
        raise Error, "owl-api returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          while (index = buffer.index("\n\n"))
            frame = buffer.slice!(0, index + 2)
            event, data = parse_sse_frame(frame)
            yield event, data if event
          end
        end
      end
    end
  rescue Error
    raise
  rescue StandardError => e
    raise Error, e.message
  end

  private

  def parse_sse_frame(frame)
    event = nil
    data = nil
    frame.each_line do |line|
      line = line.chomp
      if line.start_with?("event: ")
        event = line.delete_prefix("event: ")
      elsif line.start_with?("data: ")
        data = JSON.parse(line.delete_prefix("data: "))
      end
    end
    [ event, data ]
  end

  def post_json(path, payload, sub:)
    uri = URI.join(base_url, path)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{service_token(sub)}"
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS
    ) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "owl-api returned #{response.code}: #{response.body}"
    end

    JSON.parse(response.body, symbolize_names: true)
  rescue StandardError => e
    raise e if e.is_a?(Error)

    raise Error, e.message
  end

  def service_token(sub)
    JwtService.encode({ sub: sub }, audience: "owl-api", expires_in: 5.minutes)
  end

  def base_url
    ENV.fetch("OWL_API_URL", "http://localhost:8000")
  end
end
