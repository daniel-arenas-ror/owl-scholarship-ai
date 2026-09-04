require "test_helper"

class JwtServiceTest < ActiveSupport::TestCase
  test "round-trips claims for the right audience" do
    token = JwtService.encode({ sub: "42" }, audience: "owl-api")
    payload, header = JwtService.decode(token, audience: "owl-api")

    assert_equal "42", payload["sub"]
    assert_equal "owl-api", payload["aud"]
    assert_equal "owl-admin", payload["iss"]
    assert_equal JwtService::KID, header["kid"]
  end

  test "rejects a token presented for the wrong audience" do
    token = JwtService.encode({ sub: "42" }, audience: "owl-api")

    assert_raises(JWT::DecodeError) do
      JwtService.decode(token, audience: "owl-admin")
    end
  end

  test "public_jwk is a well-formed RSA JWK matching the signing key" do
    jwk = JwtService.public_jwk

    assert_equal "RSA", jwk[:kty]
    assert_equal "sig", jwk[:use]
    assert_equal JwtService::KID, jwk[:kid]
    assert jwk[:n].present?
    assert jwk[:e].present?
  end
end
