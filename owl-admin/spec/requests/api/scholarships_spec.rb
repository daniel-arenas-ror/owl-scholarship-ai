require "rails_helper"

RSpec.describe "Api::Scholarships", type: :request do
  let(:user) { create(:user, email: "browse@example.com") }
  let(:token) { JwtService.encode({ sub: user.id.to_s }, audience: "owl-admin") }
  let(:auth_headers) { { "Authorization" => "Bearer #{token}" } }

  let!(:daad) do
    create_scholarship(title: "Becas DAAD", provider: "DAAD", levels: [ "maestría", "doctorado" ])
  end
  let!(:chevening) do
    create_scholarship(title: "Beca Chevening", provider: "Gobierno del Reino Unido", levels: [ "maestría" ])
  end

  it "lists everything with no query" do
    get api_scholarships_path, headers: auth_headers
    expect(response).to have_http_status(:success)

    titles = JSON.parse(response.body).map { |s| s["title"] }
    expect(titles).to include("Becas DAAD", "Beca Chevening")
  end

  it "filters by title, provider, or level" do
    get api_scholarships_path(q: "chevening"), headers: auth_headers
    expect(JSON.parse(response.body).map { |s| s["title"] }).to eq([ "Beca Chevening" ])

    get api_scholarships_path(q: "doctorado"), headers: auth_headers
    expect(JSON.parse(response.body).map { |s| s["title"] }).to eq([ "Becas DAAD" ])
  end

  it "shows one scholarship's public fields, no body_markdown" do
    get api_scholarship_path(daad), headers: auth_headers
    expect(response).to have_http_status(:success)

    body = JSON.parse(response.body)
    expect(body["title"]).to eq("Becas DAAD")
    expect(body["levels"]).to eq(%w[maestría doctorado])
    expect(body).not_to have_key("body_markdown")
  end

  it "requires auth" do
    get api_scholarships_path
    expect(response).to have_http_status(:unauthorized)
  end
end
