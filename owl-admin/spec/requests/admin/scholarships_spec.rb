require "rails_helper"

RSpec.describe "Admin scholarships", type: :request do
  include_context "signed in admin"

  let!(:scholarship) do
    create_scholarship(
      source: "beca.gov.co",
      source_url: "https://beca.gov.co/x",
      title: "Beca Original",
      provider: "Proveedor",
      levels: [ "maestría" ]
    )
  end

  it "lists scholarships from owl-api's table" do
    get admin_scholarships_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Beca Original")
  end

  it "shows the scholarship" do
    get admin_scholarship_path(scholarship)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Beca Original")
    expect(response.body).to include(scholarship.id.to_s)
  end

  it "sends the edited fields to owl-api's ingest endpoint" do
    ingested = nil
    allow(OwlApiClient).to receive(:ingest) do |payload|
      ingested = payload
      { scholarship_id: scholarship.id.to_s, chunks: 4, action: "updated" }
    end

    patch admin_scholarship_path(scholarship), params: { scholarship: {
      title: "Beca Editada",
      deadline: "Marzo 2027",
      levels_text: "maestría\ndoctorado",
      fields_text: "Ingeniería, Ciencias",
      body_markdown: scholarship.body_markdown
    } }

    expect(response).to redirect_to(admin_scholarship_path(scholarship))
    follow_redirect!
    expect(response.body).to include("Enviado a owl-api (updated)")

    # the payload owl-api received carries the edits (owl-api is the writer)
    expect(ingested["title"]).to eq("Beca Editada")
    expect(ingested["deadline"]).to eq("Marzo 2027")
    expect(ingested["levels"]).to eq(%w[maestría doctorado])
    expect(ingested["fields"]).to eq([ "Ingeniería", "Ciencias" ])
    expect(ingested).not_to have_key("content_hash") # owl-api computes it
  end

  it "rejects a blank required field before calling owl-api" do
    expect(OwlApiClient).not_to receive(:ingest)

    patch admin_scholarship_path(scholarship), params: { scholarship: { title: "" } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows an owl-api error on the edit form" do
    allow(OwlApiClient).to receive(:ingest).and_raise(OwlApiClient::Error, "422 bad payload")

    patch admin_scholarship_path(scholarship), params: { scholarship: { title: "Nueva" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("owl-api rechazó")
  end

  it "requires an admin" do
    sign_out admin
    get admin_scholarships_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
