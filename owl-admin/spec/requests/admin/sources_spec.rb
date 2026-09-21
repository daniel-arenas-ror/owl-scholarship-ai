require "rails_helper"

RSpec.describe "Admin sources", type: :request do
  include_context "signed in admin"

  it "shows scholarship counts and lets you toggle enabled" do
    source = Source.for_url("https://icetex.gov.co/x")
    create_scholarship(source: "icetex.gov.co", source_url: "https://icetex.gov.co/x", title: "Beca ICETEX")

    get admin_sources_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("icetex.gov.co")

    patch admin_source_path(source), params: { source: { enabled: false } }
    expect(response).to redirect_to(admin_sources_path)
    expect(source.reload.enabled?).to be(false)
  end
end
