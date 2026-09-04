class Api::ConversationsController < Api::BaseController
  def create
    conversation = current_user.conversations.create!
    render json: conversation.as_json_public, status: :created
  end

  def show
    conversation = current_user.conversations.find(params[:id])
    render json: conversation.as_json_public(include_messages: true)
  end
end
