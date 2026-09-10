require "json"
require "fileutils"

module FineTuning
  # Builds the SFT corpus for an OpenAI fine-tuning job from the turns admins
  # have blessed: a 👍 with no annotation, an annotation marked `good`, or an
  # annotation with an `ideal_response` (best signal — "here's what it should
  # have said", regardless of verdict).
  #
  # Output is OpenAI chat format, one JSON object per line:
  #   {"messages": [{"role":"system",…},{"role":"user",…},…,{"role":"assistant",…}]}
  #
  # Run it with:  bin/rails fine_tuning:export
  class Exporter
    HISTORY_TURNS = 6
    VAL_FRACTION = 0.15
    OPENAI_MIN_EXAMPLES = 10

    # Only for turns collected before the `generation` column existed. Keep it
    # roughly in sync with owl-api/app/graph.py GENERAL_SYSTEM_PROMPT.
    FALLBACK_SYSTEM_PROMPT =
      "Eres Owl, un asistente que ayuda a estudiantes colombianos a encontrar becas. " \
      "Responde en español, de forma breve y concreta, usando únicamente la información " \
      "de becas provista. Si la información no alcanza, dilo con honestidad. Texto plano, " \
      "sin Markdown."

    Result = Struct.new(:total, :by_reason, :train_path, :val_path, :approx_tokens, keyword_init: true) do
      def summary
        lines = [ "fine-tuning export — #{total} example(s)" ]
        by_reason.sort.each { |reason, n| lines << format("  %-16s %d", reason, n) }
        if total.zero?
          lines << "nothing to export yet — collect 👍 / annotations in /admin first"
        else
          lines << "  ~#{approx_tokens} tokens"
          lines << "  train: #{train_path}"
          lines << "  val:   #{val_path}" if val_path
          if total < OPENAI_MIN_EXAMPLES
            lines << "WARNING: OpenAI needs at least #{OPENAI_MIN_EXAMPLES} examples — keep collecting."
          end
        end
        lines.join("\n")
      end
    end

    def initialize(out_dir: nil)
      @out_dir = out_dir || Rails.root.join("tmp/fine_tuning").to_s
    end

    def run
      examples = build_examples
      by_reason = examples.group_by { |e| e[:reason] }.transform_values(&:size)

      return Result.new(total: 0, by_reason: by_reason, approx_tokens: 0) if examples.empty?

      FileUtils.mkdir_p(@out_dir)
      stamp = Time.current.strftime("%Y%m%d-%H%M%S")
      train, val = split(examples)

      train_path = write(examples: train, path: File.join(@out_dir, "sft-#{stamp}.jsonl"))
      val_path = val.any? ? write(examples: val, path: File.join(@out_dir, "sft-#{stamp}-val.jsonl")) : nil

      Result.new(
        total: examples.size,
        by_reason: by_reason,
        train_path: train_path,
        val_path: val_path,
        approx_tokens: approx_tokens(examples)
      )
    end

    private

    def build_examples
      candidates
        .filter_map { |message| example_for(message) }
    end

    # Assistant messages an admin has blessed, newest first.
    def candidates
      Message.assistant
        .includes(:annotation, :feedback, conversation: :messages)
        .order(created_at: :desc)
    end

    def example_for(message)
      target, reason = target_and_reason(message)
      return nil unless target

      history = history_messages(message)
      return nil unless history.last&.dig(:role) == "user" # must end on the prompt turn

      {
        reason: reason,
        chat: {
          messages: [
            { role: "system", content: message.system_prompt.presence || FALLBACK_SYSTEM_PROMPT },
            *history,
            { role: "assistant", content: target }
          ]
        }
      }
    end

    def target_and_reason(message)
      annotation = message.annotation
      if annotation&.ideal_response.present?
        [ annotation.ideal_response, "ideal_response" ]
      elsif annotation&.good?
        [ message.content, "annotated_good" ]
      elsif annotation.nil? && message.feedback&.up?
        [ message.content, "thumbs_up" ]
      end
    end

    def history_messages(message)
      message.conversation.messages
        .select { |m| m.created_at < message.created_at }
        .sort_by(&:created_at)
        .last(HISTORY_TURNS * 2)
        .map { |m| { role: m.user? ? "user" : "assistant", content: m.content } }
    end

    def split(examples)
      return [ examples, [] ] if examples.size < OPENAI_MIN_EXAMPLES

      shuffled = examples.shuffle(random: Random.new(42))
      val_size = [ (examples.size * VAL_FRACTION).round, 1 ].max
      [ shuffled.drop(val_size), shuffled.take(val_size) ]
    end

    def write(examples:, path:)
      File.open(path, "w") do |file|
        examples.each { |e| file.puts(JSON.generate(e[:chat])) }
      end
      path
    end

    def approx_tokens(examples)
      chars = examples.sum { |e| e[:chat][:messages].sum { |m| m[:content].to_s.length } }
      (chars / 4.0).round
    end
  end
end
