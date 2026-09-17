class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :validatable

  enum :role, { student: 0, admin: 1 }

  # Set only by Internal::UsersController#update_profile — the agent's
  # profile_collector node (owl-api), authenticated with the shared secret.
  PROFILE_ATTRIBUTES = %w[full_name phone degrees].freeze

  has_many :conversations, dependent: :destroy
  has_many :annotations, foreign_key: :annotator_id, inverse_of: :annotator, dependent: :destroy

  def as_json_public
    { id: id, email: email, role: role }
  end

  # What owl-api reads/writes over the internal channel, and what it folds
  # into the system prompt so the agent can personalize without asking again.
  def profile_json
    { full_name: full_name, email: email, phone: phone, degrees: degrees }
  end
end
