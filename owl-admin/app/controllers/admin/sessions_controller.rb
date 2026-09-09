# Plain email/password sign-in for the admin app — no Devise view coupling, and
# it rejects non-admins at the door.
class Admin::SessionsController < ApplicationController
  layout "admin"

  def new
    redirect_to admin_root_path and return if user_signed_in? && current_user.admin?
  end

  def create
    user = User.find_by(email: params.dig(:user, :email).to_s.strip.downcase)

    if user&.valid_password?(params.dig(:user, :password)) && user.admin?
      sign_in(user)
      redirect_to admin_root_path, notice: "Sesión iniciada."
    else
      flash.now[:alert] = "Correo o contraseña incorrectos, o la cuenta no es de administrador."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out(current_user)
    redirect_to new_user_session_path, notice: "Sesión cerrada."
  end
end
