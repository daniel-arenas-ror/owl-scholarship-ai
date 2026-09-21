require "rails_helper"

RSpec.describe Source, type: :model do
  subject { build(:source) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:host) }
  it { is_expected.to validate_uniqueness_of(:host) }

  describe ".for_url" do
    it "finds or creates by host, stripping www" do
      a = described_class.for_url("https://www.icetex.gov.co/becas/x")
      b = described_class.for_url("https://icetex.gov.co/otra")

      expect(a.host).to eq("icetex.gov.co")
      expect(b.id).to eq(a.id)
      expect(a.name).to eq("icetex.gov.co")
    end

    it "returns nil for a junk url" do
      expect(described_class.for_url("not a url")).to be_nil
    end
  end

  describe "#record_scrape!" do
    it "stamps status" do
      source = described_class.for_url("https://x.test/a")
      source.record_scrape!(status: "error", error: "boom")

      expect(source.last_status).to eq("error")
      expect(source.last_error).to eq("boom")
      expect(source).not_to be_healthy
      expect(source.last_scraped_at).not_to be_nil
    end
  end

  describe "#healthy?" do
    it "is healthy with no scrape yet, or after an ok one" do
      source = build(:source, last_status: nil)
      expect(source).to be_healthy

      source.last_status = "ok"
      expect(source).to be_healthy
    end
  end
end
