# Guards the Internal:: namespace — owl-api calling owl-admin, the reverse
# direction of the JWT trust boundary in JwtAuthenticatable. Two narrow
# endpoints don't justify a second signing key + JWKS the other way, so this
# is a single shared secret instead, compared in constant time.
module InternalAuthenticatable
  extend ActiveSupport::Concern

  def authenticate_internal!
    render_unauthorized unless internal_secret_configured? && valid_secret?
  end

  private

  def valid_secret?
    ActiveSupport::SecurityUtils.secure_compare(bearer_token.to_s, expected_secret)
  end

  def bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.split(" ", 2).last
  end

  def expected_secret
    ENV.fetch("OWL_INTERNAL_SECRET", "")
  end

  def internal_secret_configured?
    expected_secret.present?
  end

  def render_unauthorized
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
