require "rails_helper"

# Flipper::UI is a mounted Rack app, not an Admin::BaseController subclass, so
# it can't run a before_action — routes.rb gates it with a request constraint
# instead. These specs prove that gate actually holds.
RSpec.describe "Admin flipper UI", type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:student) { create(:user) }

  it "lets an admin reach the flag management UI" do
    sign_in admin
    get "/admin/flipper"
    expect(response).to redirect_to("/admin/flipper/features") # Flipper::UI's own root redirect

    follow_redirect!
    expect(response).to have_http_status(:success)
    expect(response.body).to include("ai_scholarship_agent")
  end

  it "redirects a signed-out visitor to login" do
    get "/admin/flipper"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "redirects a signed-in non-admin to login too" do
    sign_in student
    get "/admin/flipper"
    expect(response).to redirect_to(new_user_session_path)
  end
end
