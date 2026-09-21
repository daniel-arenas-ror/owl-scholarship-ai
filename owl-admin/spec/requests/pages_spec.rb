require "rails_helper"

RSpec.describe "Pages", type: :request do
  it "renders the home page" do
    get root_path
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Owl Admin")
  end

  it "is green on the health check" do
    get rails_health_check_path
    expect(response).to have_http_status(:success)
  end
end
