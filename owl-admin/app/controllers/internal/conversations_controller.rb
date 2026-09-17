# Called only by owl-api's send_conversation_email tool. owl-admin already
# owns the full transcript (it persists every turn itself), so the tool just
# says "send #123" — no conversation content ever needs to cross back into
# owl-api.
class Internal::ConversationsController < Internal::BaseController
  def email
    conversation = Conversation.find(params[:id])
    ConversationMailer.transcript(conversation).deliver_now
    render json: { status: "sent" }
  rescue ActiveRecord::RecordNotFound
    raise # handled by Internal::BaseController's rescue_from -> 404
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
