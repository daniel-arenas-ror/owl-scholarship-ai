class Admin::DashboardController < Admin::BaseController
  def show
    @users_total = User.count
    @admins_total = User.admin.count
    @conversations_total = Conversation.count
    @assistant_messages_total = Message.assistant.count

    ratings = Feedback.group(:rating).count
    @thumbs_up = ratings["up"].to_i
    @thumbs_down = ratings["down"].to_i
    @rated_total = @thumbs_up + @thumbs_down

    @annotations_total = Annotation.count
    @scholarships_total = ScholarshipRecord.count
    @scholarships_pending = ScholarshipRecord.pending_push.count
    @sources_total = Source.count
    @sources_unhealthy = Source.where.not(last_status: [ nil, "ok" ]).count

    @recent_conversations = Conversation.includes(:user).order(created_at: :desc).limit(8)
  end
end
