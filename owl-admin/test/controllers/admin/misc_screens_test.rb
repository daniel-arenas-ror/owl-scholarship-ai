require "test_helper"

# Users list, sources health panel, and the satisfaction dashboard.
class Admin::MiscScreensTest < ActionDispatch::IntegrationTest
  include SignedInAdmin

  test "users index shows each user with a conversation count" do
    student = User.create!(email: "pat@example.com", password: "password123")
    student.conversations.create!

    get admin_users_path
    assert_response :success
    assert_match "pat@example.com", response.body
    assert_match @admin.email, response.body
  end

  test "sources index shows record counts and lets you toggle enabled" do
    source = Source.for_url("https://icetex.gov.co/x")
    ScholarshipRecord.upsert_from_payload(
      "source_url" => "https://icetex.gov.co/x", "title" => "B", "provider" => "P",
      "country" => "CO", "fields" => [], "levels" => [], "body_markdown" => "texto suficiente aquí"
    )

    get admin_sources_path
    assert_response :success
    assert_match "icetex.gov.co", response.body

    patch admin_source_path(source), params: { source: { enabled: false } }
    assert_redirected_to admin_sources_path
    assert_not source.reload.enabled?
  end

  test "satisfaction dashboard aggregates by agent and renders charts" do
    student = User.create!(email: "q@example.com", password: "password123")
    conversation = student.conversations.create!
    %w[general_advisor scholarship_expert].each_with_index do |agent, i|
      msg = conversation.messages.create!(role: :assistant, content: "r#{i}", agent: agent,
        citations: [ { "scholarship_id" => "1", "title" => "Chevening", "source_url" => "x" } ])
      msg.create_feedback!(rating: i.zero? ? :up : :down)
    end

    get admin_satisfaction_path
    assert_response :success
    assert_match "Satisfacción", response.body
    assert_match "Chevening", response.body
    # chartkick renders a div with data-* the JS picks up
    assert_select "[id^=chart-]"
  end
end
