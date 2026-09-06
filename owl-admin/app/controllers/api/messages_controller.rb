class Api::MessagesController < Api::BaseController
  def feedback
    message = Message.joins(:conversation)
                      .where(conversations: { user_id: current_user.id })
                      .find(params[:id])

    fb = message.feedback || message.build_feedback
    fb.rating = params[:rating]
    fb.reason = params[:reason]
    fb.save!

    render json: { feedback: fb.as_json_public }, status: :ok
  rescue ArgumentError
    render json: { error: "rating must be \"up\" or \"down\"" }, status: :unprocessable_entity
  end
end
