class Message < ApplicationRecord
  belongs_to :conversation
  has_one :feedback, dependent: :destroy
  enum :role, { user: 0, assistant: 1 }

  validates :content, presence: true

  def as_json_public
    {
      id: id,
      role: role,
      content: content,
      agent: agent,
      citations: citations,
      feedback: feedback&.as_json_public,
      created_at: created_at
    }
  end
end
