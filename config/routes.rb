Rails.application.routes.draw do
  # Devise authentication
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    registrations: "users/registrations",
    sessions: "users/sessions"
  }

  # Root path
  root "home#index"
  get "favicon.ico", to: proc { [ 204, { "Content-Type" => "image/x-icon" }, [] ] }

  # Static pages
  get "about", to: "pages#about"
  get "guidelines", to: "pages#guidelines"
  get "contact", to: "pages#contact"

  # Main feed
  get "feed", to: "feed#index"
  get "feed/trending", to: "feed#trending"
  get "feed/following", to: "feed#following"
  get "feed/threads",   to: "feed#threads"

  # Rooms
  resources :rooms, only: [ :index, :show ] do
    member do
      post :join
      delete :leave
    end
    resources :posts, only: [ :index ], module: :rooms
  end

  # Posts
  resources :posts do
    collection do
      post :check_gentleness
      post :suggest_scripture
    end
    member do
      post :feature
      post :unfeature
      get  :inline_thread
      post :join_prayer_chain
      delete :leave_prayer_chain
      post :mark_prayer_answered
    end
    resources :comments, only: [ :create, :update, :destroy ] do
      member do
        post :reply
      end
    end
    resource :bookmark, only: [ :create, :destroy ]
    resource :reshare, only: [ :create, :destroy ]
  end

  # Likes (polymorphic)
  post "likes/:likeable_type/:likeable_id", to: "likes#create", as: :likes
  delete "likes/:likeable_type/:likeable_id", to: "likes#destroy", as: :unlike
  resources :reports, only: [ :create ]

  # Mentions autocomplete
  get "mentions", to: "users#mentions"

  # User profiles
  resources :users, only: [ :show ], param: :username, path: "u" do
    member do
      post :follow
      delete :unfollow
      get :followers
      get :following
      get :posts
    end
  end

  # Resources section
  namespace :resources do
    root to: "home#index"
  end

  resources :resource_items, path: "resources", as: :resources_items

  resources :resource_categories, only: [ :index, :show ]

  # Bookmarks
  get "bookmarks", to: "bookmarks#index"
  get "drafts", to: "drafts#index", as: :drafts
  get "scripture/lookup", to: "scripture#show", as: :scripture_lookup
  post "bible/search", to: "bible#search", as: :bible_search

  # Games / leaderboard
  get  "games",                  to: "games#index",            as: :games
  get  "games/quiz",             to: "games#quiz",             as: :games_quiz
  post "games/quiz/generate",    to: "games#quiz_generate",    as: :games_quiz_generate
  post "games/quiz/submit",      to: "games#quiz_submit",      as: :games_quiz_submit
  get  "games/chess",            to: "games#chess",            as: :games_chess
  post "games/chess/solved",     to: "games#chess_solved",     as: :games_chess_solved
  get  "games/trivia",           to: "games#trivia",           as: :games_trivia
  post "games/trivia/generate",  to: "games#trivia_generate",  as: :games_trivia_generate
  post "games/trivia/submit",    to: "games#trivia_submit",    as: :games_trivia_submit

  resources :reading_plans, only: [ :index, :show ], param: :slug do
    member do
      post :start
      post :check_in
      delete :leave
    end
  end

  # Notifications
  resources :notifications, only: [ :index ] do
    collection do
      post :mark_all_read
      get  :popover
    end
    member do
      post :mark_read
    end
  end
  resources :invitations, only: [ :index, :create ] do
    member do
      post :resend
    end
    collection do
      post :bulk
    end
  end

  # Search
  get "search", to: "search#index"
  get "people", to: "users#index", as: :people

  # Settings
  namespace :settings do
    get "/", to: redirect("/settings/profile/edit")
    resource :profile, only: [ :edit, :update ]
    resource :account, only: [ :edit, :update ]
    resource :notifications, only: [ :edit, :update ]
    resource :privacy, only: [ :edit, :update ]
    resource :brethren_card, only: [ :edit, :update ]
    resource :dark_mode, only: [ :update ]
  end

  # Brethren Card & Connection Requests
  resources :brethren_cards, only: [ :show ], param: :username
  resources :connection_requests, only: [ :index, :create ] do
    member do
      post :accept
      post :decline
    end
  end
  get "my-connections", to: "connection_requests#connections", as: :my_connections

  get "inbox/search", to: "conversations#search", as: :inbox_search
  resources :conversations, path: "inbox", only: [ :index, :show, :create ] do
    member do
      post :archive
      post :mark_read
    end
    resources :messages, only: [ :create, :update, :destroy ]
  end
  resources :message_blocks, only: [ :create, :destroy ], param: :user_id

  # Admin namespace
  namespace :admin do
    root to: "dashboard#index"
    resources :users do
      member do
        post :suspend
        post :activate
        post :make_moderator
        post :make_admin
      end
    end
    resources :rooms
    resources :posts do
      member do
        post :feature
        post :unfeature
      end
    end
    resources :resources do
      member do
        post :approve
        post :reject
      end
    end
    resources :reports, only: [ :index, :show ] do
      member do
        post :resolve
        post :dismiss
      end
    end
    resources :moderation_logs, only: [ :index, :show ]
    resources :bible_verses do
      member { post :toggle }
    end
    resources :golden_breaths do
      member { post :toggle }
    end
    resources :moderation_reviews, only: [ :index, :show ] do
      member do
        post :decide
        post :copilot
      end
    end
    resources :broadcasts do
      member do
        post :send_now
      end
    end
    resources :announcements, only: [ :index, :new, :create, :destroy ]
  end

  # Web Push subscriptions — endpoint-keyed (client doesn't know its row id).
  post   "/push_subscriptions",     to: "push_subscriptions#create",  as: :push_subscriptions
  delete "/push_subscriptions",     to: "push_subscriptions#destroy"
  get    "/push_subscriptions/key", to: "push_subscriptions#key",     as: :push_subscriptions_key

  # PWA
  get "/manifest.webmanifest", to: "pwa#manifest", defaults: { format: :json }, as: :pwa_manifest
  get "/service-worker.js",    to: "pwa#service_worker"
  get "/offline",              to: "pwa#offline", as: :offline

  # Token-signed email unsubscribe links (no auth required)
  get "/email/unsubscribe/weekly-digest/:token",
      to: "email_unsubscribes#weekly_digest",
      as: :email_unsubscribes_weekly_digest

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
