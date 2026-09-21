require "rails_helper"

RSpec.describe "Admin users", type: :request do
  include_context "signed in admin"

  it "shows each user with a conversation count" do
    student = create(:user, email: "pat@example.com")
    student.conversations.create!

    get admin_users_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("pat@example.com")
    expect(response.body).to include(admin.email)
  end
end
