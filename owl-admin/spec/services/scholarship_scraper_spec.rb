require "rails_helper"

RSpec.describe ScholarshipScraper do
  let(:page) do
    <<~HTML
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
  end

  it "normalizes a page into the wire-field payload" do
    payload = described_class.new("https://fulbright.edu.co/beca", html: page).scrape(dry_run: true)

    expect(payload["source"]).to eq("fulbright.edu.co")
    expect(payload["source_url"]).to eq("https://fulbright.edu.co/beca")
    expect(payload["title"]).to eq("Beca Fulbright para colombianos")
    expect(payload["provider"]).to eq("Comisión Fulbright Colombia")
    expect(payload["country"]).to eq("CO")
    expect(payload["fields"]).to eq([])
    expect(payload["external_id"]).to be_nil
    expect(payload["body_markdown"]).to be_present
  end

  it "keeps headings and list items, drops nav/script/footer" do
    payload = described_class.new("https://fulbright.edu.co/beca", html: page).scrape(dry_run: true)
    body = payload["body_markdown"]

    expect(body).to include("# Beca Fulbright")
    expect(body).to include("## Requisitos")
    expect(body).to include("- Ser colombiano.")
    expect(body).to include("financia estudios de maestría y doctorado")
    expect(body).not_to include("track()")
    expect(body).not_to include("Inicio Contacto")
    expect(body).not_to include("© Fulbright")
  end

  it "pushes to owl-api, stamps the Source, and returns the ingest result" do
    ingested = nil
    allow(OwlApiClient).to receive(:ingest) do |payload|
      ingested = payload
      { scholarship_id: "42", chunks: 3, action: "created" }
    end

    result = described_class.new("https://fulbright.edu.co/beca", html: page).scrape

    expect(result[:action]).to eq("created")
    expect(ingested["source_url"]).to eq("https://fulbright.edu.co/beca")
    expect(ingested["title"]).to eq("Beca Fulbright para colombianos")
    expect(ingested).not_to have_key("content_hash") # owl-api computes it

    source = Source.find_by(host: "fulbright.edu.co")
    expect(source.last_status).to eq("ok")
    expect(source.last_scraped_at).not_to be_nil
  end

  it "marks the source unhealthy and re-raises on an owl-api failure" do
    allow(OwlApiClient).to receive(:ingest).and_raise(OwlApiClient::Error, "boom")

    expect do
      described_class.new("https://fulbright.edu.co/beca", html: page).scrape
    end.to raise_error(OwlApiClient::Error)

    expect(Source.find_by(host: "fulbright.edu.co").last_status).to eq("error")
  end

  it "does not touch owl-api on a dry run" do
    expect(OwlApiClient).not_to receive(:ingest)

    payload = described_class.new("https://fulbright.edu.co/beca", html: page).scrape(dry_run: true)

    expect(payload["title"]).to eq("Beca Fulbright para colombianos")
  end

  it "falls back title and provider to the host when the page has no metadata" do
    bare = "<html><body><main>#{'texto de la convocatoria ' * 20}</main></body></html>"
    payload = described_class.new("https://www.becas-ejemplo.gov.co/x", html: bare).scrape(dry_run: true)

    expect(payload["source"]).to eq("becas-ejemplo.gov.co")
    expect(payload["title"]).to eq("becas-ejemplo.gov.co")
    expect(payload["provider"]).to eq("becas-ejemplo.gov.co")
  end

  it "raises when the extracted body is too short to be real content" do
    scraper = described_class.new("https://x.test/p", html: "<html><body><p>Cargando…</p></body></html>")

    expect { scraper.scrape(dry_run: true) }.to raise_error(described_class::Error, /only \d+ chars/)
  end

  it "rejects a non-http url up front" do
    expect { described_class.new("ftp://example.com/x") }.to raise_error(described_class::Error)
    expect { described_class.new("") }.to raise_error(described_class::Error)
  end
end
