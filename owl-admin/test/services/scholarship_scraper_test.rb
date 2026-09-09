require "test_helper"

class ScholarshipScraperTest < ActiveSupport::TestCase
  PAGE = <<~HTML.freeze
    <!doctype html>
    <html lang="es">
      <head>
        <title>Beca Fulbright Colombia | Comisión Fulbright</title>
        <meta property="og:title" content="Beca Fulbright para colombianos">
        <meta property="og:site_name" content="Comisión Fulbright Colombia">
      </head>
      <body>
        <nav>Inicio Contacto <script>track()</script></nav>
        <main>
          <h1>Beca Fulbright</h1>
          <p>La beca Fulbright financia estudios de <strong>maestría</strong> y
             doctorado en los Estados Unidos para ciudadanos colombianos.</p>
          <h2>Requisitos</h2>
          <ul>
            <li>Ser colombiano.</li>
            <li>Tener título profesional.</li>
          </ul>
          <p>Las convocatorias abren cada año; revisa el calendario oficial para
             las fechas exactas de cierre y los montos vigentes del programa.</p>
        </main>
        <footer>© Fulbright</footer>
      </body>
    </html>
  HTML

  test "normalizes a page into the wire-field payload" do
    payload = ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape(dry_run: true)

    assert_equal "fulbright.edu.co", payload["source"]
    assert_equal "https://fulbright.edu.co/beca", payload["source_url"]
    assert_equal "Beca Fulbright para colombianos", payload["title"]
    assert_equal "Comisión Fulbright Colombia", payload["provider"]
    assert_equal "CO", payload["country"]
    assert_equal [], payload["fields"]
    assert_nil payload["external_id"]
    assert payload["body_markdown"].present?
  end

  test "extracted body keeps headings and list items, drops nav/script/footer" do
    payload = ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape(dry_run: true)
    body = payload["body_markdown"]

    assert_includes body, "# Beca Fulbright"
    assert_includes body, "## Requisitos"
    assert_includes body, "- Ser colombiano."
    assert_includes body, "financia estudios de maestría y doctorado"
    refute_includes body, "track()"
    refute_includes body, "Inicio Contacto"
    refute_includes body, "© Fulbright"
  end

  test "persists a ScholarshipRecord + Source and pushes to owl-api" do
    record = with_stubbed_ingest({ scholarship_id: "42", chunks: 3, action: "created" }) do
      ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape
    end

    assert_instance_of ScholarshipRecord, record
    assert record.persisted?
    assert_equal "fulbright.edu.co", record.source.host
    assert_equal "42", record.owl_api_scholarship_id
    assert_equal "created", record.last_push_status
    assert_equal "ok", record.source.last_status
    assert_equal "https://fulbright.edu.co/beca", @ingested["source_url"]
    assert_equal "Beca Fulbright para colombianos", @ingested["title"]
  end

  test "a second scrape of the same url updates the one record" do
    with_stubbed_ingest({ scholarship_id: "42", chunks: 3, action: "created" }) do
      ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape
      ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape
    end

    assert_equal 1, ScholarshipRecord.where(source_url: "https://fulbright.edu.co/beca").count
  end

  test "an owl-api failure marks the source unhealthy and re-raises" do
    assert_raises(OwlApiClient::Error) do
      with_stubbed_ingest(-> { raise OwlApiClient::Error, "boom" }) do
        ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape
      end
    end

    record = ScholarshipRecord.find_by(source_url: "https://fulbright.edu.co/beca")
    assert_equal "error", record.last_push_status
    assert_equal "error", record.source.last_status
  end

  test "dry_run does not touch owl-api" do
    payload = with_stubbed_ingest(-> { flunk "ingest should not be called on a dry run" }) do
      ScholarshipScraper.new("https://fulbright.edu.co/beca", html: PAGE).scrape(dry_run: true)
    end

    assert_equal "Beca Fulbright para colombianos", payload["title"]
  end

  test "title and provider fall back to the host when the page has no metadata" do
    bare = "<html><body><main>#{'texto de la convocatoria ' * 20}</main></body></html>"
    payload = ScholarshipScraper.new("https://www.becas-ejemplo.gov.co/x", html: bare).scrape(dry_run: true)

    assert_equal "becas-ejemplo.gov.co", payload["source"]
    assert_equal "becas-ejemplo.gov.co", payload["title"]
    assert_equal "becas-ejemplo.gov.co", payload["provider"]
  end

  test "raises when the extracted body is too short to be real content" do
    error = assert_raises(ScholarshipScraper::Error) do
      ScholarshipScraper.new("https://x.test/p", html: "<html><body><p>Cargando…</p></body></html>").scrape(dry_run: true)
    end
    assert_match(/only \d+ chars/, error.message)
  end

  test "rejects a non-http url up front" do
    assert_raises(ScholarshipScraper::Error) { ScholarshipScraper.new("ftp://example.com/x") }
    assert_raises(ScholarshipScraper::Error) { ScholarshipScraper.new("") }
  end

  private

  # Swaps OwlApiClient.ingest for the block's duration. `stub` is either the
  # result Hash to return (with the payload captured in @ingested), or a
  # zero-arg lambda run for its side effect — used to assert it is never called.
  def with_stubbed_ingest(stub)
    original = OwlApiClient.method(:ingest)
    test = self
    OwlApiClient.define_singleton_method(:ingest) do |payload|
      next stub.call if stub.respond_to?(:call)

      test.instance_variable_set(:@ingested, payload)
      stub
    end
    yield
  ensure
    OwlApiClient.define_singleton_method(:ingest, original)
  end
end
