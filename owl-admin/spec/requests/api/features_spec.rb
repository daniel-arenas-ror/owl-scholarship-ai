require "rails_helper"

RSpec.describe "Api::Features", type: :request do
  after { Flipper.enable(Features::AI_SCHOLARSHIP_AGENT) }

  it "reports the current ai_scholarship_agent state with no auth required" do
    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
    get api_features_path
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)).to eq("ai_scholarship_agent" => true)

    Flipper.disable(Features::AI_SCHOLARSHIP_AGENT)
    get api_features_path
    expect(JSON.parse(response.body)).to eq("ai_scholarship_agent" => false)
  end
end
