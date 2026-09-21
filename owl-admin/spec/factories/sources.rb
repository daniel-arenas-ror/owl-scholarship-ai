FactoryBot.define do
  factory :source do
    sequence(:host) { |n| "source#{n}.example.com" }
    name { host }
    enabled { true }
  end
end
