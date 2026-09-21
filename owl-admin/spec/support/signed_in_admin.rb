# `include_context "signed in admin"` in a request spec to get a persisted,
# signed-in `admin` (Devise session cookie already set).
RSpec.shared_context "signed in admin" do
  let!(:admin) do
    create(:user, :admin, email: "admin-#{SecureRandom.hex(4)}@example.com")
  end

  before { sign_in admin }
end
