require "digest"

namespace :scholarships do
  desc "Push db/seeds/scholarships.json to owl-api (chunk + embed + store in pgvector)"
  task seed: :environment do
    path = Rails.root.join("db/seeds/scholarships.json")
    records = JSON.parse(File.read(path))

    records.each do |record|
      payload = record.merge(
        "content_hash" => Digest::SHA256.hexdigest(record["body_markdown"]),
        "last_seen_at" => Time.now.utc.iso8601
      )

      result = OwlApiClient.ingest(payload)
      puts format("%-9s %-60s (%d chunks)", result[:action], record["title"], result[:chunks])
    rescue OwlApiClient::Error => e
      puts "FAILED    #{record['title']}: #{e.message}"
    end
  end
end
