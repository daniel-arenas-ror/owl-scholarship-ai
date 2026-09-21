FactoryBot.define do
  factory :feedback do
    association :message, :assistant
    rating { :up }
  end
end
