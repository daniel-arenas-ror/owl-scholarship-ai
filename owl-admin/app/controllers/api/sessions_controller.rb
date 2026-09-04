# Stateless JWT "sessions" — no server-side session store to invalidate.
class Api::SessionsController < ActionController::API
  def create
    user = User.find_by(email: params[:email].to_s.downcase)

    if user&.valid_password?(params[:password].to_s)
      render json: { token: issue_token(user), user: user.as_json_public }, status: :created
    else
      render json: { error: "invalid email or password" }, status: :unauthorized
    end
  end

  # Nothing to revoke server-side yet; the client just discards the token.
  def destroy
    head :no_content
  end

  private

  def issue_token(user)
    JwtService.encode({ sub: user.id.to_s, email: user.email, role: user.role }, audience: "owl-admin")
  end
end
