FactoryBot.define do
  factory :message do
    conversation
    role { :user }
    content { "hola" }

    trait :assistant do
      role { :assistant }
      content { "respuesta" }
    end
  end
end
