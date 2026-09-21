require "rails_helper"

RSpec.describe Conversation, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:messages).dependent(:destroy) }

  it "orders messages by created_at" do
    conversation = create(:conversation)
    second = create(:message, conversation: conversation, content: "segundo")
    first = create(:message, conversation: conversation, content: "primero")
    first.update_column(:created_at, second.created_at - 1.hour)

    expect(conversation.messages.to_a).to eq([ first, second ])
  end

  describe "#as_json_public" do
    it "omits messages by default" do
      conversation = create(:conversation, title: "Becas en Alemania")

      expect(conversation.as_json_public).to eq(
        id: conversation.id, title: "Becas en Alemania", created_at: conversation.created_at
      )
    end

    it "includes each message's public shape when asked" do
      conversation = create(:conversation)
      message = create(:message, conversation: conversation, content: "hola")

      result = conversation.as_json_public(include_messages: true)

      expect(result[:messages]).to eq([ message.as_json_public ])
    end
  end
end
