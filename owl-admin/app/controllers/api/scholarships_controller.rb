# The "browse and search" surface for owl-web when AI_SCHOLARSHIP_AGENT is
# off: a plain list of everything in the shared `scholarships` table, filtered
# by a search term. Same table the admin inventory and the chat agent read —
# see app/models/scholarship.rb.
class Api::ScholarshipsController < Api::BaseController
  LIMIT = 200

  def index
    scholarships = Scholarship.search(params[:q]).order(:title).limit(LIMIT)
    render json: scholarships.map(&:as_json_public)
  end

  def show
    render json: Scholarship.find(params[:id]).as_json_public
  end
end
