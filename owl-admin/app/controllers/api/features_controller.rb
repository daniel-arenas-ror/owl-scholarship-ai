# Public — just tells the browser which UI to render (chat agent vs. plain
# scholarship search), not sensitive. No Bearer auth, so owl-web can decide
# before the user even logs in.
class Api::FeaturesController < ActionController::API
  def show
    render json: { ai_scholarship_agent: Features.ai_scholarship_agent? }
  end
end
