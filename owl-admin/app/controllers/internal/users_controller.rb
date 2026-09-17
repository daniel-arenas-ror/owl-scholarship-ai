# Called only by owl-api's OwlAdminClient (profile_collector node + the
# per-turn hydrate-on-miss read into the InMemoryStore).
class Internal::UsersController < Internal::BaseController
  before_action :set_user

  def show_profile
    render json: @user.profile_json
  end

  def update_profile
    @user.update!(profile_params)
    render json: @user.profile_json
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def profile_params
    params.permit(:full_name, :phone, degrees: [])
  end
end
