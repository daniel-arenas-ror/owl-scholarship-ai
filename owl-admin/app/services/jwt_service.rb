require "base64"

# Signs and verifies the RS256 JWTs owl-admin issues — one shape for the
# browser's own session (aud: "owl-admin") and one for calls to owl-api
# (aud: "owl-api"). owl-api verifies independently against +public_jwk+,
# published at GET /.well-known/jwks.json.
class JwtService
  KID = "owl-admin-1"
  ISSUER = "owl-admin"

  class << self
    def encode(claims, audience:, expires_in: 24.hours)
      now = Time.now.to_i
      payload = claims.merge(
        iss: ISSUER,
        aud: audience,
        iat: now,
        exp: now + expires_in.to_i
      )
      JWT.encode(payload, private_key, "RS256", { kid: KID, typ: "JWT" })
    end

    def decode(token, audience:)
      JWT.decode(
        token,
        public_key,
        true,
        algorithm: "RS256",
        iss: ISSUER,
        verify_iss: true,
        aud: audience,
        verify_aud: true
      )
    end

    def jwks
      { keys: [ public_jwk ] }
    end

    # Hand-built per RFC 7518 rather than via JWT::JWK, so the shape is exact
    # and doesn't drift with ruby-jwt's own JWK API across versions.
    def public_jwk
      {
        kty: "RSA",
        use: "sig",
        alg: "RS256",
        kid: KID,
        n: Base64.urlsafe_encode64(public_key.n.to_s(2), padding: false),
        e: Base64.urlsafe_encode64(public_key.e.to_s(2), padding: false)
      }
    end

    private

    def private_key
      @private_key ||= OpenSSL::PKey::RSA.new(private_pem)
    end

    def public_key
      private_key.public_key
    end

    # Production: OWL_JWT_PRIVATE_KEY (PEM) from SSM. Dev: a keypair generated
    # once and cached on disk so tokens survive a server restart.
    def private_pem
      ENV["OWL_JWT_PRIVATE_KEY"].presence || dev_key_file
    end

    def dev_key_file
      path = Rails.root.join("config/jwt/private_key.pem")
      FileUtils.mkdir_p(path.dirname)
      unless File.exist?(path)
        File.write(path, OpenSSL::PKey::RSA.new(2048).to_pem)
        File.chmod(0o600, path)
      end
      File.read(path)
    end
  end
end
