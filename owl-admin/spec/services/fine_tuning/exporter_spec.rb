require "rails_helper"

RSpec.describe FineTuning::Exporter do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:out_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(out_dir) }

  # One user turn + one assistant turn in a fresh conversation.
  def turn(user_text:, assistant_text:, system_prompt: "SYS-PROMPT", model_variant: "base")
    convo = user.conversations.create!
    convo.messages.create!(role: :user, content: user_text)
    convo.messages.create!(
      role: :assistant, content: assistant_text,
      generation: { "system_prompt" => system_prompt, "model_variant" => model_variant }
    )
  end

  it "has nothing to export when there are no blessed turns" do
    turn(user_text: "hola", assistant_text: "respuesta sin feedback")

    result = described_class.new(out_dir: out_dir).run

    expect(result.total).to eq(0)
    expect(result.summary).to include("nothing to export yet")
    expect(Dir.children(out_dir)).to be_empty
  end

  it "picks up 👍, annotated-good, and ideal-response turns" do
    up = turn(user_text: "becas alemania", assistant_text: "Considera DAAD.")
    up.create_feedback!(rating: :up)

    good = turn(user_text: "becas francia", assistant_text: "Considera Eiffel.")
    good.create_annotation!(verdict: :good, annotator: admin)

    ideal = turn(user_text: "becas uk", assistant_text: "respuesta floja")
    ideal.create_annotation!(verdict: :bad, annotator: admin,
      ideal_response: "Chevening: maestría de un año, exige 2 años de experiencia.")

    result = described_class.new(out_dir: out_dir).run

    expect(result.total).to eq(3)
    expect(result.by_reason).to eq(
      "thumbs_up" => 1, "annotated_good" => 1, "ideal_response" => 1
    )
    expect(result.approx_tokens).to be_positive

    lines = File.readlines(result.train_path).map { |l| JSON.parse(l) }
    expect(lines.size).to eq(3)

    ideal_example = lines.find do |ex|
      ex["messages"].first["content"] == "SYS-PROMPT" &&
        ex["messages"].any? { |m| m["content"] == "becas uk" }
    end
    expect(ideal_example["messages"][0]["role"]).to eq("system")
    expect(ideal_example["messages"][1]["role"]).to eq("user")
    expect(ideal_example["messages"].last["role"]).to eq("assistant")
    # the ideal response, not the weak original, is the training target
    expect(ideal_example["messages"].last["content"]).to eq(
      "Chevening: maestría de un año, exige 2 años de experiencia."
    )
  end

  it "skips a bad annotation with no ideal response" do
    bad = turn(user_text: "x", assistant_text: "mala respuesta")
    bad.create_annotation!(verdict: :bad, annotator: admin)

    expect(described_class.new(out_dir: out_dir).run.total).to eq(0)
  end

  it "skips a 👎 turn" do
    down = turn(user_text: "x", assistant_text: "respuesta")
    down.create_feedback!(rating: :down)

    expect(described_class.new(out_dir: out_dir).run.total).to eq(0)
  end

  it "warns and skips the val split below OpenAI's minimum" do
    5.times { |i| turn(user_text: "p#{i}", assistant_text: "r#{i}").create_feedback!(rating: :up) }

    result = described_class.new(out_dir: out_dir).run

    expect(result.total).to eq(5)
    expect(result.val_path).to be_nil
    expect(result.summary).to match(/WARNING.*at least 10/)
  end

  it "falls back to the stock system prompt when generation is absent" do
    convo = user.conversations.create!
    convo.messages.create!(role: :user, content: "hola")
    legacy = convo.messages.create!(role: :assistant, content: "respuesta antigua") # no generation
    legacy.create_feedback!(rating: :up)

    result = described_class.new(out_dir: out_dir).run
    example = JSON.parse(File.readlines(result.train_path).first)

    expect(example["messages"].first["content"]).to include("Eres Owl")
  end
end
