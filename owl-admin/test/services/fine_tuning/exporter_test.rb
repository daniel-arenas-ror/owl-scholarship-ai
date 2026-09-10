require "test_helper"

class FineTuning::ExporterTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "student@example.com", password: "password123")
    @admin = User.create!(email: "admin@example.com", password: "password123", role: :admin)
    @out_dir = Dir.mktmpdir
  end

  teardown { FileUtils.remove_entry(@out_dir) }

  # One user turn + one assistant turn in a fresh conversation.
  def turn(user_text:, assistant_text:, system_prompt: "SYS-PROMPT", model_variant: "base")
    convo = @user.conversations.create!
    convo.messages.create!(role: :user, content: user_text)
    convo.messages.create!(
      role: :assistant, content: assistant_text,
      generation: { "system_prompt" => system_prompt, "model_variant" => model_variant }
    )
  end

  test "nothing to export when there are no blessed turns" do
    turn(user_text: "hola", assistant_text: "respuesta sin feedback")

    result = FineTuning::Exporter.new(out_dir: @out_dir).run

    assert_equal 0, result.total
    assert_match "nothing to export yet", result.summary
    assert_empty Dir.children(@out_dir)
  end

  test "picks up 👍, annotated-good, and ideal-response turns" do
    up = turn(user_text: "becas alemania", assistant_text: "Considera DAAD.")
    up.create_feedback!(rating: :up)

    good = turn(user_text: "becas francia", assistant_text: "Considera Eiffel.")
    good.create_annotation!(verdict: :good, annotator: @admin)

    ideal = turn(user_text: "becas uk", assistant_text: "respuesta floja")
    ideal.create_annotation!(verdict: :bad, annotator: @admin,
      ideal_response: "Chevening: maestría de un año, exige 2 años de experiencia.")

    result = FineTuning::Exporter.new(out_dir: @out_dir).run

    assert_equal 3, result.total
    assert_equal({ "thumbs_up" => 1, "annotated_good" => 1, "ideal_response" => 1 }, result.by_reason)
    assert result.approx_tokens.positive?

    lines = File.readlines(result.train_path).map { |l| JSON.parse(l) }
    assert_equal 3, lines.size

    ideal_example = lines.find { |ex| ex["messages"].first["content"] == "SYS-PROMPT" &&
      ex["messages"].any? { |m| m["content"] == "becas uk" } }
    assert_equal "system", ideal_example["messages"][0]["role"]
    assert_equal "user", ideal_example["messages"][1]["role"]
    assert_equal "assistant", ideal_example["messages"].last["role"]
    # the ideal response, not the weak original, is the training target
    assert_equal "Chevening: maestría de un año, exige 2 años de experiencia.",
      ideal_example["messages"].last["content"]
  end

  test "a bad annotation with no ideal response is skipped" do
    bad = turn(user_text: "x", assistant_text: "mala respuesta")
    bad.create_annotation!(verdict: :bad, annotator: @admin)

    assert_equal 0, FineTuning::Exporter.new(out_dir: @out_dir).run.total
  end

  test "a 👎 turn is skipped" do
    down = turn(user_text: "x", assistant_text: "respuesta")
    down.create_feedback!(rating: :down)

    assert_equal 0, FineTuning::Exporter.new(out_dir: @out_dir).run.total
  end

  test "warns and skips the val split below OpenAI's minimum" do
    5.times { |i| turn(user_text: "p#{i}", assistant_text: "r#{i}").create_feedback!(rating: :up) }

    result = FineTuning::Exporter.new(out_dir: @out_dir).run

    assert_equal 5, result.total
    assert_nil result.val_path
    assert_match(/WARNING.*at least 10/, result.summary)
  end

  test "falls back to the stock system prompt when generation is absent" do
    convo = @user.conversations.create!
    convo.messages.create!(role: :user, content: "hola")
    legacy = convo.messages.create!(role: :assistant, content: "respuesta antigua") # no generation
    legacy.create_feedback!(rating: :up)

    result = FineTuning::Exporter.new(out_dir: @out_dir).run
    example = JSON.parse(File.readlines(result.train_path).first)

    assert_includes example["messages"].first["content"], "Eres Owl"
  end
end
