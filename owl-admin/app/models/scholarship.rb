# owl-api's `scholarships` table, read (and lightly edited) straight from the
# admin app. There is only ONE scholarship table in the system — this is it.
#
# Writes don't go through ActiveRecord: the admin edit form hands the record to
# owl-api's ingest endpoint (`OwlApiClient.ingest`), which re-chunks and
# re-embeds. So editing is always consistent with the vectors, and owl-admin
# never has to know the pgvector column even exists.
class Scholarship < OwlApiRecord
  self.table_name = "scholarships"

  # pgvector lives on scholarship_chunks, not here, but be defensive.
  self.ignored_columns += %w[embedding]

  EDITABLE_ATTRIBUTES = %w[
    title provider country funding_type amount_note deadline eligibility_text
    body_markdown external_id
  ].freeze

  # Virtual fields the edit form uses for the array columns (newline/comma text).
  attr_accessor :fields_text, :levels_text

  scope :recent, -> { order(updated_at: :desc) }

  validates :title, :provider, :body_markdown, presence: true

  # The payload owl-api's ingest endpoint expects. No content_hash — owl-api
  # computes it from these fields, so any edit triggers a re-embed.
  def to_ingest_payload
    {
      "source" => source,
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
      "last_seen_at" => Time.current.utc.iso8601
    }
  end
end
