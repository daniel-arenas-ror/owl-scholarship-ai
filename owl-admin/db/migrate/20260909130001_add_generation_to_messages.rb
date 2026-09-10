class AddGenerationToMessages < ActiveRecord::Migration[8.1]
  def change
    # What owl-api reported about how this answer was produced: the exact system
    # prompt (system + retrieved context) and which model variant answered
    # ("base" / "finetuned"). Raw material for the Phase 6 fine-tuning export.
    add_column :messages, :generation, :jsonb, null: false, default: {}
  end
end
