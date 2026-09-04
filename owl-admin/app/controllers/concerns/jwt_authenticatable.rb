module JwtAuthenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  def authenticate_user!
    token = bearer_token
    return render_unauthorized unless token

    payload = JwtService.decode(token, audience: "owl-admin").first
    @current_user = User.find_by(id: payload["sub"])
    render_unauthorized unless @current_user
  rescue JWT::DecodeError
    render_unauthorized
  end

  private

  def bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.split(" ", 2).last
  end

  def render_unauthorized
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
