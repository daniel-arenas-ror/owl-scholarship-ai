class Admin::UsersController < Admin::BaseController
  def index
    @users = User
      .left_joins(:conversations)
      .select("users.*, COUNT(conversations.id) AS conversations_count")
      .group("users.id")
      .order("users.created_at DESC")
  end
end
