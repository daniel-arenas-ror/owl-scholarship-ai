namespace :scholarships do
  desc "Push db/seeds/scholarships.json to owl-api (chunk + embed + store in pgvector)"
  task seed: :environment do
    path = Rails.root.join("db/seeds/scholarships.json")
    records = JSON.parse(File.read(path))

    records.each do |record|
      # owl-api computes content_hash from the wire fields itself.
      result = OwlApiClient.ingest(record.merge("last_seen_at" => Time.now.utc.iso8601))
      puts format("%-9s %-60s (%d chunks)", result[:action], record["title"], result[:chunks])
    rescue OwlApiClient::Error => e
      puts "FAILED    #{record['title']}: #{e.message}"
    end
  end
end
