require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page renders" do
    get root_path
    assert_response :success
    assert_select "h1", "Owl Admin"
  end

  test "health check is green" do
    get rails_health_check_path
    assert_response :success
  end
end
