require "rails_helper"

RSpec.describe Feedback, type: :model do
  it { is_expected.to belong_to(:message) }
  it { is_expected.to define_enum_for(:rating).with_values(down: 0, up: 1) }

  describe "#as_json_public" do
    it "exposes the rating and reason" do
      feedback = build(:feedback, rating: :down, reason: "muy corto")
      expect(feedback.as_json_public).to eq(rating: "down", reason: "muy corto")
    end
  end
end
