# Sends a student their own conversation, triggered by the agent's
# email_sender node (owl-api) via Internal::ConversationsController#email.
class ConversationMailer < ApplicationMailer
  def transcript(conversation)
    @conversation = conversation
    @messages = conversation.messages.order(:created_at)
    mail(
      to: conversation.user.email,
      subject: "Tu conversación con Owl — #{conversation.title.presence || "##{conversation.id}"}"
    )
  end
end
