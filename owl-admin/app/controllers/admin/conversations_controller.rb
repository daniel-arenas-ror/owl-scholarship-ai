class Admin::ConversationsController < Admin::BaseController
  LIMIT = 100

  # TODO: Add pagination to this endpoint, and allow filtering by user_id, date range, etc.
  def index
    @conversations = Conversation
      .includes(:user)
      .left_joins(:messages)
      .select("conversations.*, COUNT(messages.id) AS messages_count, MAX(messages.created_at) AS last_activity_at")
      .group("conversations.id")
      .order(Arel.sql("MAX(messages.created_at) DESC NULLS LAST"))
      .limit(LIMIT)
  end

  def show
    @conversation = Conversation.includes(messages: [ :feedback, :annotation ]).find(params[:id])
    @messages = @conversation.messages
  end
end
