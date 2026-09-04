class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, -> { order(:created_at) }, dependent: :destroy

  def as_json_public(include_messages: false)
    base = { id: id, title: title, created_at: created_at }
    return base unless include_messages

    base.merge(messages: messages.map(&:as_json_public))
  end
end
