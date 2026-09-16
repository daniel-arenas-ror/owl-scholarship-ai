require "test_helper"

class Api::ScholarshipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "browse@example.com", password: "password123")
    @token = JwtService.encode({ sub: @user.id.to_s }, audience: "owl-admin")
    @daad = create_scholarship(title: "Becas DAAD", provider: "DAAD",
      levels: [ "maestría", "doctorado" ])
    @chevening = create_scholarship(title: "Beca Chevening", provider: "Gobierno del Reino Unido",
      levels: [ "maestría" ])
  end

  test "index lists everything with no query, ordered by title" do
    get api_scholarships_path, headers: auth_headers
    assert_response :success

    titles = JSON.parse(response.body).map { |s| s["title"] }
    assert_includes titles, "Becas DAAD"
    assert_includes titles, "Beca Chevening"
  end

  test "index filters by title, provider, or level" do
    get api_scholarships_path(q: "chevening"), headers: auth_headers
    assert_equal [ "Beca Chevening" ], JSON.parse(response.body).map { |s| s["title"] }

    get api_scholarships_path(q: "doctorado"), headers: auth_headers
    assert_equal [ "Becas DAAD" ], JSON.parse(response.body).map { |s| s["title"] }
  end

  test "show returns one scholarship's public fields, no body_markdown" do
    get api_scholarship_path(@daad), headers: auth_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "Becas DAAD", body["title"]
    assert_equal %w[maestría doctorado], body["levels"]
    assert_not body.key?("body_markdown")
  end

  test "requires auth" do
    get api_scholarships_path
    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end
end
