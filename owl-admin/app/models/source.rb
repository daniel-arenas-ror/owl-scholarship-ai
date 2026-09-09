class Source < ApplicationRecord
  validates :name, presence: true
  validates :host, presence: true, uniqueness: true

  scope :enabled, -> { where(enabled: true) }

  # Find (or create) the source a scraped URL belongs to, keyed by host.
  def self.for_url(url)
    host = URI.parse(url.to_s).host.to_s.sub(/\Awww\./, "")
    return nil if host.blank?

    find_or_create_by!(host: host) { |source| source.name = host }
  rescue URI::InvalidURIError
    nil
  end

  def record_scrape!(status:, error: nil)
    update!(last_scraped_at: Time.current, last_status: status, last_error: error)
  end

  def healthy?
    last_status.nil? || last_status == "ok"
  end
end
