class Admin::AnnotationsController < Admin::BaseController
  before_action :set_message

  def create
    annotation = @message.build_annotation(annotation_params.merge(annotator: current_user))
    persist(annotation)
  end

  def update
    annotation = @message.annotation || @message.build_annotation(annotator: current_user)
    annotation.assign_attributes(annotation_params)
    persist(annotation)
  end

  def destroy
    @message.annotation&.destroy
    redirect_back fallback_location: admin_conversation_path(@message.conversation),
      notice: "Anotación eliminada."
  end

  private

  def set_message
    @message = Message.find(params[:message_id])
  end

  def persist(annotation)
    if annotation.save
      redirect_back fallback_location: admin_conversation_path(@message.conversation),
        notice: "Anotación guardada."
    else
      redirect_back fallback_location: admin_conversation_path(@message.conversation),
        alert: annotation.errors.full_messages.to_sentence
    end
  end

  def annotation_params
    params.require(:annotation).permit(:verdict, :ideal_response, :note)
  end
end
