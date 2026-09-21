require "rails_helper"

RSpec.describe Annotation, type: :model do
  it { is_expected.to belong_to(:message) }
  it { is_expected.to belong_to(:annotator).class_name("User") }
  it { is_expected.to define_enum_for(:verdict).with_values(bad: 0, good: 1) }
  it { is_expected.to validate_presence_of(:verdict) }

  it "allows only one annotation per message" do
    message = create(:message, :assistant)
    create(:annotation, message: message)

    dup = build(:annotation, message: message)

    expect(dup).not_to be_valid
    expect(dup.errors[:message_id]).to include("has already been taken")
  end
end
