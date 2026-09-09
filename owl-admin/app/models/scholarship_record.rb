require "digest"

# owl-admin's canonical copy of a scholarship. Created only by the scraper
# (`ScholarshipScraper`); admins can edit the wire fields here and then push the
# change to owl-api, which re-chunks and re-embeds it. owl-api stays the source
# of truth for retrieval — this table is the inventory the admin app works with.
class ScholarshipRecord < ApplicationRecord
  WIRE_ATTRIBUTES = %w[
    source_url external_id title provider country fields levels
    funding_type amount_note deadline eligibility_text body_markdown
  ].freeze

  EDITABLE_ATTRIBUTES = (WIRE_ATTRIBUTES - %w[source_url]).freeze

  belongs_to :source, optional: true

  # Virtual fields the edit form uses for the array columns (newline/comma text).
  attr_accessor :fields_text, :levels_text

  validates :source_url, presence: true, uniqueness: true
  validates :title, :provider, :body_markdown, presence: true
  validates :country, presence: true

  before_validation :normalize_arrays
  before_validation :recompute_content_hash

  scope :pending_push, -> { where("pushed_content_hash IS DISTINCT FROM content_hash") }
  scope :recently_scraped, -> { order(updated_at: :desc) }

  # Upsert from a scraped payload (string-keyed, the same hash sent to owl-api).
  def self.upsert_from_payload(payload)
    record = find_or_initialize_by(source_url: payload["source_url"])
    record.assign_attributes(payload.slice(*WIRE_ATTRIBUTES))
    record.source = Source.for_url(payload["source_url"])
    record.save!
    record
  end

  def pending_push?
    pushed_content_hash != content_hash
  end

  def synced?
    pushed_content_hash.present? && !pending_push?
  end

  def to_ingest_payload
    {
      "source" => source&.host || URI.parse(source_url).host.to_s.sub(/\Awww\./, ""),
      "source_url" => source_url,
      "external_id" => external_id,
      "title" => title,
      "provider" => provider,
      "country" => country,
      "fields" => Array(fields),
      "levels" => Array(levels),
      "funding_type" => funding_type,
      "amount_note" => amount_note,
      "deadline" => deadline,
      "eligibility_text" => eligibility_text,
      "body_markdown" => body_markdown,
      "content_hash" => content_hash,
      "last_seen_at" => Time.current.utc.iso8601
    }
  end

  # Push the current state to owl-api's ingest endpoint. Returns the parsed
  # result on success; records the failure and re-raises on OwlApiClient::Error.
  def push_to_owl_api!
    result = OwlApiClient.ingest(to_ingest_payload)
    update!(
      owl_api_scholarship_id: result[:scholarship_id],
      pushed_content_hash: content_hash,
      last_pushed_at: Time.current,
      last_push_status: result[:action],
      last_push_error: nil
    )
    result
  rescue OwlApiClient::Error => e
    update!(last_pushed_at: Time.current, last_push_status: "error", last_push_error: e.message)
    raise
  end

  private

  def normalize_arrays
    self.fields = Array(fields).map { |value| value.to_s.strip }.reject(&:blank?)
    self.levels = Array(levels).map { |value| value.to_s.strip }.reject(&:blank?)
  end

  # Hash every wire field, not just the body — so an edit to the deadline or the
  # funding note also marks the record as needing a push to owl-api.
  def recompute_content_hash
    digest_input = WIRE_ATTRIBUTES.map do |attr|
      value = public_send(attr)
      value.is_a?(Array) ? value.join("␟") : value.to_s
    end.join("␞")
    self.content_hash = Digest::SHA256.hexdigest(digest_input)
  end
end
