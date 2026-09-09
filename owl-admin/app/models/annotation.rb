# An admin's judgement on one assistant message, plus the ideal reply. This is
# the raw material for the Phase 6 fine-tuning corpus (SFT from `good` + ideal
# replies, DPO pairs from `good` / `bad` on similar prompts).
class Annotation < ApplicationRecord
  belongs_to :message
  belongs_to :annotator, class_name: "User"

  enum :verdict, { bad: 0, good: 1 }

  validates :verdict, presence: true
  validates :message_id, uniqueness: true
end
