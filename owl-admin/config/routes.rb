Rails.application.routes.draw do
  # Devise supplies the User model's modules; we ship our own JSON controllers
  # below instead of Devise's HTML session/registration views.
  devise_for :users, skip: :all

  # HTML session routes for the admin app (session cookie, not the API JWT).
  devise_scope :user do
    get    "/admin/login"  => "admin/sessions#new",     as: :new_user_session
    post   "/admin/login"  => "admin/sessions#create",  as: :user_session
    delete "/admin/logout" => "admin/sessions#destroy", as: :destroy_user_session
  end

  namespace :admin do
    root "dashboard#show"
    get "satisfaction", to: "satisfaction#show"

    resources :conversations, only: [ :index, :show ]
    resources :users, only: [ :index ]
    resources :sources, only: [ :index, :update ]
    resources :scholarships, only: [ :index, :show, :edit, :update ] do
      member { post :push }
    end
    resources :messages, only: [] do
      resource :annotation, only: [ :create, :update, :destroy ]
    end
  end

  get "/.well-known/jwks.json" => "jwks#show"

  namespace :api do
    resource :session, only: [ :create, :destroy ]
    resources :registrations, only: [ :create ]

    resources :conversations, only: [ :create, :show ] do
      resources :messages, only: [ :create ], module: :conversations
    end

    resources :messages, only: [] do
      member { post :feedback }
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
