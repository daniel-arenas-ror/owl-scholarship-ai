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

  # Case-insensitive match on title/provider, or any one field/level — powers
  # owl-web's plain "browse and search" screen (AI_SCHOLARSHIP_AGENT off).
  scope :search, lambda { |query|
    next all if query.blank?

    like = "%#{sanitize_sql_like(query)}%"
    where(<<~SQL.squish, like: like)
      title ILIKE :like
      OR provider ILIKE :like
      OR EXISTS (SELECT 1 FROM unnest(fields) AS f WHERE f ILIKE :like)
      OR EXISTS (SELECT 1 FROM unnest(levels) AS l WHERE l ILIKE :like)
    SQL
  }

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

  # What the browser gets from GET /api/scholarships(/:id) — the "browse and
  # search" screen owl-web shows when AI_SCHOLARSHIP_AGENT is off. No
  # body_markdown (long free text); the admin app is where you'd read that.
  def as_json_public
    {
      id: id,
      title: title,
      provider: provider,
      country: country,
      fields: Array(fields),
      levels: Array(levels),
      funding_type: funding_type,
      amount_note: amount_note,
      deadline: deadline,
      eligibility_text: eligibility_text,
      source_url: source_url
    }
  end
end
