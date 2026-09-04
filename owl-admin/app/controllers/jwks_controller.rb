class JwksController < ActionController::API
  def show
    render json: JwtService.jwks
  end
end
