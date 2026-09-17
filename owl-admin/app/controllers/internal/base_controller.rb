class Internal::BaseController < ActionController::API
  include InternalAuthenticatable

  before_action :authenticate_internal!
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    render json: { error: "not found" }, status: :not_found
  end
end
