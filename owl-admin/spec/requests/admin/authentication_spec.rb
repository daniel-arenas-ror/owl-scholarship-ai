require "rails_helper"

RSpec.describe "Admin authentication", type: :request do
  let!(:admin) { create(:user, :admin, email: "admin@example.com") }
  let!(:student) { create(:user, email: "student@example.com") }

  it "redirects admin routes to login when signed out" do
    get admin_root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets a valid admin sign in and reach the panel" do
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }
    expect(response).to redirect_to(admin_root_path)

    follow_redirect!
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Panel")
  end

  it "refuses a student at the login form" do
    post user_session_path, params: { user: { email: student.email, password: "password123" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to match(/administrador/)

    get admin_root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "rejects a wrong password" do
    post user_session_path, params: { user: { email: admin.email, password: "nope" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "lets a signed-in admin sign out" do
    sign_in admin
    delete destroy_user_session_path
    expect(response).to redirect_to(new_user_session_path)

    get admin_root_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
