require "rails_helper"

RSpec.describe User, type: :model do
  it { is_expected.to have_many(:conversations).dependent(:destroy) }
  it { is_expected.to have_many(:annotations).with_foreign_key(:annotator_id).dependent(:destroy) }

  it "requires a unique email" do
    create(:user, email: "dup@example.com")
    dup = build(:user, email: "dup@example.com")

    expect(dup).not_to be_valid
    expect(dup.errors[:email]).to include("has already been taken")
  end

  it "defaults to the student role" do
    expect(create(:user)).to be_student
  end

  it "as_json_public never leaks the password" do
    user = create(:user, email: "safe@example.com")
    expect(user.as_json_public).to eq(id: user.id, email: "safe@example.com", role: "student")
  end

  it "profile_json exposes the agent-collected fields plus the account email" do
    user = create(:user, email: "profile@example.com",
      full_name: "Maria Lopez", phone: "3001234567", degrees: [ "Ingeniería" ])

    expect(user.profile_json).to eq(
      full_name: "Maria Lopez", email: "profile@example.com", phone: "3001234567", degrees: [ "Ingeniería" ]
    )
  end

  it "degrees defaults to an empty array" do
    expect(create(:user).degrees).to eq([])
  end
end
