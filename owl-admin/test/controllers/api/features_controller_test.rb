require "test_helper"

class Api::FeaturesControllerTest < ActionDispatch::IntegrationTest
  test "reports the current ai_scholarship_agent state with no auth required" do
    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
    get api_features_path
    assert_response :success
    assert_equal({ "ai_scholarship_agent" => true }, JSON.parse(response.body))

    Flipper.disable(Features::AI_SCHOLARSHIP_AGENT)
    get api_features_path
    assert_equal({ "ai_scholarship_agent" => false }, JSON.parse(response.body))
  ensure
    Flipper.enable(Features::AI_SCHOLARSHIP_AGENT)
  end
end
