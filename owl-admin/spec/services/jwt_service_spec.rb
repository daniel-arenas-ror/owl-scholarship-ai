require "rails_helper"

RSpec.describe JwtService do
  it "round-trips claims for the right audience" do
    token = described_class.encode({ sub: "42" }, audience: "owl-api")
    payload, header = described_class.decode(token, audience: "owl-api")

    expect(payload["sub"]).to eq("42")
    expect(payload["aud"]).to eq("owl-api")
    expect(payload["iss"]).to eq("owl-admin")
    expect(header["kid"]).to eq(described_class::KID)
  end

  it "rejects a token presented for the wrong audience" do
    token = described_class.encode({ sub: "42" }, audience: "owl-api")

    expect { described_class.decode(token, audience: "owl-admin") }.to raise_error(JWT::DecodeError)
  end

  it "public_jwk is a well-formed RSA JWK matching the signing key" do
    jwk = described_class.public_jwk

    expect(jwk[:kty]).to eq("RSA")
    expect(jwk[:use]).to eq("sig")
    expect(jwk[:kid]).to eq(described_class::KID)
    expect(jwk[:n]).to be_present
    expect(jwk[:e]).to be_present
  end
end
