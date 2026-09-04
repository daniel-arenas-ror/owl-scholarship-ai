Rails.application.routes.draw do
  # Devise supplies the User model's modules; we ship our own JSON controllers
  # below instead of Devise's HTML session/registration views.
  devise_for :users, skip: :all

  get "/.well-known/jwks.json" => "jwks#show"

  namespace :api do
    resource :session, only: [ :create, :destroy ]
    resources :registrations, only: [ :create ]

    resources :conversations, only: [ :create, :show ] do
      resources :messages, only: [ :create ], module: :conversations
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
