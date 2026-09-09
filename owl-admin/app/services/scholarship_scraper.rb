require "net/http"
require "uri"
require "nokogiri"

# Fetches a single scholarship page by URL, pulls a readable text body plus a
# few headline fields out of the HTML, upserts a local ScholarshipRecord (linked
# to its Source), and pushes it to owl-api's ingest endpoint (chunk + embed +
# store in pgvector) via OwlApiClient.
#
# Console use:
#   ScholarshipScraper.new("https://www.icetex.gov.co/...").scrape  # -> ScholarshipRecord
#   ScholarshipScraper.new(url).scrape(dry_run: true)      # normalize only, no writes
#   ScholarshipScraper.new(url, html: "<html>...").scrape  # skip the fetch entirely
#
# Generic readability-style extraction — no per-site parser. Creating a
# ScholarshipRecord is the scraper's job alone; admins edit records in the admin
# app and re-push from there. A later phase wraps this in a GoodJob job to re-run
# it on a schedule; for now it is a plain object you call by hand.
class ScholarshipScraper
  class Error < StandardError; end

  USER_AGENT = "OwlScholarshipBot/0.1 (+https://owl.example; scholarship indexer)".freeze
  OPEN_TIMEOUT_SECONDS = 10
  READ_TIMEOUT_SECONDS = 20
  MAX_REDIRECTS = 3
  # A body shorter than this is almost always a bot wall, a JS-only shell, or an
  # error page rather than real scholarship content.
  MIN_BODY_LENGTH = 200

  # Tags removed wholesale before text extraction.
  STRIP_TAGS = %w[script style noscript template svg iframe form nav aside].freeze
  HEADING_PREFIX = { "h1" => "# ", "h2" => "## ", "h3" => "### ",
                     "h4" => "#### ", "h5" => "##### ", "h6" => "###### " }.freeze
  # Block-level tags that force a paragraph break after their content.
  BREAK_AFTER = %w[p div section article header footer ul ol li tr table
                   blockquote pre h1 h2 h3 h4 h5 h6].freeze

  attr_reader :url

  def self.scrape(url, **options)
    new(url).scrape(**options)
  end

  def initialize(url, html: nil)
    @url = url.to_s.strip
    @html = html
    raise Error, "url is required" if @url.empty?
    raise Error, "url must be http(s), got #{@url.inspect}" unless @url.match?(%r{\Ahttps?://}i)

    @uri = URI.parse(@url)
  rescue URI::InvalidURIError => e
    raise Error, "invalid url: #{e.message}"
  end

  # Upserts a ScholarshipRecord, pushes it to owl-api, and returns the record.
  # With dry_run: true, returns the normalized payload that *would* be persisted
  # instead of writing anything — handy for iterating in the console.
  def scrape(dry_run: false)
    document = Nokogiri::HTML(html)
    payload = normalize(document)

    return payload if dry_run

    record = ScholarshipRecord.upsert_from_payload(payload)
    begin
      record.push_to_owl_api!
      record.source&.record_scrape!(status: "ok")
    rescue OwlApiClient::Error => e
      record.source&.record_scrape!(status: "error", error: e.message)
      raise
    end
    record
  end

  private

  def html
    @html ||= fetch(@url)
  end

  def fetch(target, redirects_left: MAX_REDIRECTS)
    uri = URI.parse(target)
    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS
    ) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "text/html,application/xhtml+xml"
      http.request(request)
    end

    case response
    when Net::HTTPSuccess
      content_type = response["content-type"].to_s
      unless content_type.empty? || content_type.include?("html")
        raise Error, "#{target} returned #{content_type.split(';').first}, expected HTML"
      end

      decode_body(response)
    when Net::HTTPRedirection
      raise Error, "too many redirects starting from #{@url}" if redirects_left.zero?

      fetch(URI.join(target, response["location"]).to_s, redirects_left: redirects_left - 1)
    else
      raise Error, "#{target} returned #{response.code} #{response.message}"
    end
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "could not fetch #{target}: #{e.message}"
  end

  def decode_body(response)
    raw = response.body.to_s
    charset = response["content-type"].to_s[/charset=([^;\s]+)/i, 1]
    encoding = (Encoding.find(charset) if charset) rescue nil
    raw.dup
       .force_encoding(encoding || Encoding::UTF_8)
       .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  def normalize(document)
    body_markdown = extract_text(document)
    if body_markdown.length < MIN_BODY_LENGTH
      raise Error, "extracted only #{body_markdown.length} chars from #{@url} — " \
                   "the page may require JavaScript or block bots"
    end

    {
      "source" => source_name,
      "source_url" => @url,
      "external_id" => nil,
      "title" => extract_title(document),
      "provider" => extract_provider(document),
      "country" => "CO",
      "fields" => [],
      "levels" => [],
      "body_markdown" => body_markdown
    }
  end

  def source_name
    @uri.host.to_s.sub(/\Awww\./, "").presence || "unknown"
  end

  def extract_title(document)
    candidates = [
      document.at_css('meta[property="og:title"]')&.[]("content"),
      document.at_css("main h1, article h1, h1")&.text,
      document.at_css("title")&.text
    ]
    candidates.filter_map { |c| c.to_s.strip.gsub(/\s+/, " ").presence }.first || source_name
  end

  def extract_provider(document)
    site_name = document.at_css('meta[property="og:site_name"]')&.[]("content").to_s.strip
    site_name.presence || source_name
  end

  def extract_text(document)
    root = document.at_css("main") || document.at_css("article") ||
           document.at_css("body") || document
    root.css(STRIP_TAGS.join(",")).remove

    buffer = +""
    render_children(root, buffer)
    buffer.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def render_children(node, buffer)
    node.children.each do |child|
      if child.text?
        append_text(child.text, buffer)
      elsif child.element?
        render_element(child, buffer)
      end
    end
  end

  def render_element(element, buffer)
    name = element.name.downcase

    case name
    when "br"
      buffer << "\n"
    when *HEADING_PREFIX.keys
      buffer << "\n\n" unless buffer.empty?
      buffer << HEADING_PREFIX.fetch(name)
      render_children(element, buffer)
      buffer << "\n\n"
    when "li"
      buffer << "\n- "
      render_children(element, buffer)
    else
      render_children(element, buffer)
      buffer << "\n\n" if BREAK_AFTER.include?(name)
    end
  end

  def append_text(text, buffer)
    collapsed = text.gsub(/\s+/, " ")
    return if collapsed.empty?

    if collapsed.strip.empty?
      buffer << " " unless buffer.empty? || buffer.end_with?(" ", "\n")
    else
      buffer << collapsed
    end
  end
end
