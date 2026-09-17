require "flipper/ui"

# Only true for a request already carrying an authenticated admin session
# cookie — used to gate the mounted Flipper::UI Rack app below, since it lives
# outside the Admin::BaseController stack and can't run a before_action.
ADMIN_SESSION = lambda do |request|
  request.env["warden"]&.user(:user)&.admin? || false
end

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
    resources :scholarships, only: [ :index, :show, :edit, :update ]
    resources :messages, only: [] do
      resource :annotation, only: [ :create, :update, :destroy ]
    end
  end

  # Flipper's own management UI (toggle AI_SCHOLARSHIP_AGENT and any future
  # flag) — gated to a signed-in admin; anyone else bounces to the login page.
  constraints(ADMIN_SESSION) do
    mount Flipper::UI.app(Flipper) => "/admin/flipper"
  end
  get "/admin/flipper" => redirect("/admin/login")
  get "/admin/flipper/*path" => redirect("/admin/login")

  # Dev-only web inbox for mail sent via config.action_mailer.delivery_method
  # = :letter_opener_web (see config/environments/development.rb) — how
  # "send this conversation to my email" gets verified with no real SMTP.
  if Rails.env.development?
    constraints(ADMIN_SESSION) do
      mount LetterOpenerWeb::Engine, at: "/letter_opener"
    end
    get "/letter_opener" => redirect("/admin/login")
    get "/letter_opener/*path" => redirect("/admin/login")
  end

  get "/.well-known/jwks.json" => "jwks#show"

  # owl-api calling owl-admin — the reverse direction of the browser -> admin
  # -> api flow, for the few things only owl-admin can do (persist a profile,
  # send mail). Shared-secret authenticated; see InternalAuthenticatable.
  namespace :internal do
    get   "users/:id/profile", to: "users#show_profile", as: "user_profile"
    patch "users/:id/profile", to: "users#update_profile", as: "update_user_profile"
    post  "conversations/:id/email", to: "conversations#email", as: "email_conversation"
  end

  namespace :api do
    resource :session, only: [ :create, :destroy ]
    resources :registrations, only: [ :create ]
    resource :features, only: [ :show ]
    resources :scholarships, only: [ :index, :show ]

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
