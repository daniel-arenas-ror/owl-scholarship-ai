class Admin::BaseController < ApplicationController
  layout "admin"

  before_action :authenticate_user!
  before_action :require_admin

  private

  def require_admin
    return if current_user&.admin?

    sign_out(current_user) if user_signed_in?
    redirect_to new_user_session_path, alert: "Necesitas una cuenta de administrador."
  end
end
