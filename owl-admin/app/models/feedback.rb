class Feedback < ApplicationRecord
  belongs_to :message
  enum :rating, { down: 0, up: 1 }

  def as_json_public
    { rating: rating, reason: reason }
  end
end
