class Api::Conversations::MessagesController < Api::BaseController
  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    user_message = conversation.messages.create!(role: :user, content: params[:content])

    result = OwlApiClient.respond(
      conversation: conversation,
      user_message: user_message,
      user_context: { country: "CO" }
    )

    assistant_message = conversation.messages.create!(
      role: :assistant,
      content: result[:message],
      agent: result[:agent],
      citations: result[:citations] || []
    )

    render json: {
      user_message: user_message.as_json_public,
      assistant_message: assistant_message.as_json_public
    }, status: :created
  rescue OwlApiClient::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end
end
