require "test_helper"

class JwksControllerTest < ActionDispatch::IntegrationTest
  test "publishes the RSA public key" do
    get "/.well-known/jwks.json"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body["keys"].length
    assert_equal "RSA", body["keys"].first["kty"]
  end
end
