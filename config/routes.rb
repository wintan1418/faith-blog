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
    member do
      post :feature
      post :unfeature
      get  :inline_thread
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

  # Notifications
  resources :notifications, only: [ :index ] do
    collection do
      post :mark_all_read
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

  resources :conversations, path: "inbox", only: [ :index, :show, :create ] do
    member do
      post :archive
      post :mark_read
    end
    resources :messages, only: [ :create ]
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
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
