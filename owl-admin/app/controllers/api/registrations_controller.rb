class Api::RegistrationsController < ActionController::API
  def create
    user = User.new(email: params[:email].to_s.downcase, password: params[:password])

    if user.save
      token = JwtService.encode({ sub: user.id.to_s, email: user.email, role: user.role }, audience: "owl-admin")
      render json: { token: token, user: user.as_json_public }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
