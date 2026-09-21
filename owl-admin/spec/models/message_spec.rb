require "rails_helper"

RSpec.describe Message, type: :model do
  it { is_expected.to belong_to(:conversation) }
  it { is_expected.to have_one(:feedback).dependent(:destroy) }
  it { is_expected.to have_one(:annotation).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:content) }
  it { is_expected.to define_enum_for(:role).with_values(user: 0, assistant: 1) }

  describe "#trace_url" do
    it "is nil with no trace_run_id" do
      expect(build(:message, trace_run_id: nil).trace_url).to be_nil
    end

    it "links to the LangSmith run in the default workspace" do
      message = build(:message, trace_run_id: "run-abc-123")

      expect(message.trace_url).to eq(
        "https://smith.langchain.com/o/-/projects/p/owl-dev/r/run-abc-123"
      )
    end
  end

  describe "#system_prompt and #model_variant" do
    it "read them from the generation jsonb" do
      message = build(:message, generation: { "system_prompt" => "SYS", "model_variant" => "finetuned" })

      expect(message.system_prompt).to eq("SYS")
      expect(message.model_variant).to eq("finetuned")
    end

    it "model_variant falls back to base when absent" do
      expect(build(:message, generation: {}).model_variant).to eq("base")
    end
  end

  describe "#as_json_public" do
    it "includes the feedback's public shape when present" do
      message = create(:message, :assistant, agent: "general_advisor", citations: [ { "title" => "DAAD" } ])
      create(:feedback, message: message, rating: :up)

      expect(message.as_json_public).to eq(
        id: message.id,
        role: "assistant",
        content: message.content,
        agent: "general_advisor",
        citations: [ { "title" => "DAAD" } ],
        feedback: { rating: "up", reason: nil },
        created_at: message.created_at
      )
    end

    it "feedback is nil when there is none" do
      expect(create(:message).as_json_public[:feedback]).to be_nil
    end
  end
end
