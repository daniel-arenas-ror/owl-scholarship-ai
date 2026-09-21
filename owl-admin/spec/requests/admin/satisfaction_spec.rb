require "rails_helper"

RSpec.describe "Admin satisfaction dashboard", type: :request do
  include_context "signed in admin"

  it "aggregates by agent and renders charts" do
    student = create(:user, email: "q@example.com")
    conversation = student.conversations.create!
    %w[general_advisor scholarship_expert].each_with_index do |agent, i|
      msg = conversation.messages.create!(role: :assistant, content: "r#{i}", agent: agent,
        citations: [ { "scholarship_id" => "1", "title" => "Chevening", "source_url" => "x" } ])
      msg.create_feedback!(rating: i.zero? ? :up : :down)
    end

    get admin_satisfaction_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Satisfacción")
    expect(response.body).to include("Chevening")
    # chartkick renders a div with data-* the JS picks up
    expect(response.body).to match(/id="chart-/)
  end
end
