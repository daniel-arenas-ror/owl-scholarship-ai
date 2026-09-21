require "rails_helper"

RSpec.describe "JWKS", type: :request do
  it "publishes the RSA public key" do
    get "/.well-known/jwks.json"
    expect(response).to have_http_status(:success)

    body = JSON.parse(response.body)
    expect(body["keys"].length).to eq(1)
    expect(body["keys"].first["kty"]).to eq("RSA")
  end
end
