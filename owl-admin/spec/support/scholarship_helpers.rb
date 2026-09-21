# Scholarship lives in owl-api's `scholarships` table (a second, unmanaged
# connection — see rails_helper.rb), which transactional fixtures don't wrap
# the same way they wrap the primary database. So each spec cleans up exactly
# the rows it made, the same way the old Minitest suite did.
module ScholarshipHelpers
  def create_scholarship(**attrs)
    record = Scholarship.create!({
      source: "example.com",
      source_url: "https://example.com/#{SecureRandom.hex(6)}",
      title: "Beca de prueba",
      provider: "Proveedor de prueba",
      country: "CO",
      fields: [],
      levels: [ "maestría" ],
      body_markdown: "Cuerpo de la beca con suficiente texto de relleno.",
      content_hash: SecureRandom.hex(16)
    }.merge(attrs))
    (@_created_scholarships ||= []) << record.id
    record
  end
end

RSpec.configure do |config|
  config.include ScholarshipHelpers

  config.after do
    Scholarship.where(id: @_created_scholarships).delete_all if @_created_scholarships.present?
  end
end
