FactoryBot.define do
  factory :annotation do
    association :message, :assistant
    association :annotator, factory: %i[user admin]
    verdict { :good }
  end
end
