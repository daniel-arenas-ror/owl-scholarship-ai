class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :validatable

  enum :role, { student: 0, admin: 1 }

  has_many :conversations, dependent: :destroy
  has_many :annotations, foreign_key: :annotator_id, inverse_of: :annotator, dependent: :destroy

  def as_json_public
    { id: id, email: email, role: role }
  end
end
