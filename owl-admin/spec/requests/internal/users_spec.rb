require "rails_helper"

RSpec.describe "Internal::Users", type: :request do
  let(:user) { create(:user, email: "student@example.com") }
  let(:secret) { "test-internal-secret" }
  let(:auth_headers) { { "Authorization" => "Bearer #{secret}" } }

  around do |example|
    ENV["OWL_INTERNAL_SECRET"] = secret
    example.run
    ENV.delete("OWL_INTERNAL_SECRET")
  end

  it "show_profile returns the profile fields" do
    user.update!(full_name: "Maria Lopez", phone: "3001234567", degrees: [ "Ingeniería" ])

    get internal_user_profile_path(user), headers: auth_headers
    expect(response).to have_http_status(:success)

    body = JSON.parse(response.body)
    expect(body["full_name"]).to eq("Maria Lopez")
    expect(body["email"]).to eq("student@example.com")
    expect(body["degrees"]).to eq([ "Ingeniería" ])
  end

  it "update_profile sets only full_name, phone, and degrees" do
    patch internal_update_user_profile_path(user),
      params: { full_name: "Maria Lopez", degrees: [ "Ingeniería", "MBA" ] }.to_json,
      headers: auth_headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:success)
    user.reload
    expect(user.full_name).to eq("Maria Lopez")
    expect(user.degrees).to eq(%w[Ingeniería MBA])
    expect(user.phone).to be_nil # untouched — not sent this time
  end

  it "update_profile cannot touch email, role, or password" do
    patch internal_update_user_profile_path(user),
      params: { email: "hijacked@example.com", role: "admin" }.to_json,
      headers: auth_headers.merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:success)
    user.reload
    expect(user.email).to eq("student@example.com")
    expect(user.role).to eq("student")
  end

  it "requires the shared secret" do
    get internal_user_profile_path(user)
    expect(response).to have_http_status(:unauthorized)

    get internal_user_profile_path(user), headers: { "Authorization" => "Bearer wrong" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses when no secret is configured" do
    ENV.delete("OWL_INTERNAL_SECRET")
    get internal_user_profile_path(user), headers: auth_headers
    expect(response).to have_http_status(:unauthorized)
  end
end
