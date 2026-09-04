class Api::BaseController < ActionController::API
  include JwtAuthenticatable

  before_action :authenticate_user!
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    render json: { error: "not found" }, status: :not_found
  end
end
