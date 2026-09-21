require "rails_helper"

# Scholarship reads owl-api's `scholarships` table over a second connection —
# see spec/support/scholarship_helpers.rb for how records are made and cleaned
# up (transactional fixtures don't reliably wrap this connection).
RSpec.describe Scholarship, type: :model do
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:body_markdown) }

  describe ".search" do
    it "matches on title, provider, or any one field/level, case-insensitively" do
      daad = create_scholarship(title: "Becas DAAD", provider: "DAAD", levels: [ "maestría", "doctorado" ])
      chevening = create_scholarship(title: "Beca Chevening", provider: "Gobierno del Reino Unido",
        levels: [ "maestría" ])

      expect(described_class.search("chevening")).to contain_exactly(chevening)
      expect(described_class.search("doctorado")).to contain_exactly(daad)
      expect(described_class.search("")).to include(daad, chevening)
    end
  end

  describe ".recent" do
    it "orders by updated_at descending" do
      older = create_scholarship
      newer = create_scholarship
      older.update_column(:updated_at, newer.updated_at - 1.day)

      expect(described_class.recent.to_a.first(2)).to eq([ newer, older ])
    end
  end

  describe "#to_ingest_payload" do
    it "carries the wire fields owl-api's ingest endpoint expects, with no content_hash" do
      scholarship = create_scholarship(fields: [ "Ingeniería" ], levels: [ "maestría" ])

      payload = scholarship.to_ingest_payload

      expect(payload["title"]).to eq(scholarship.title)
      expect(payload["fields"]).to eq([ "Ingeniería" ])
      expect(payload["levels"]).to eq([ "maestría" ])
      expect(payload).not_to have_key("content_hash")
    end
  end

  describe "#as_json_public" do
    it "exposes the browse fields but never body_markdown" do
      scholarship = create_scholarship(title: "Beca Original")

      expect(scholarship.as_json_public).not_to have_key(:body_markdown)
      expect(scholarship.as_json_public[:title]).to eq("Beca Original")
    end
  end
end
