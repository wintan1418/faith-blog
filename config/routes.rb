Rails.application.routes.draw do
  # Devise authentication
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions'
  }

  # Root path
  root "home#index"

  # Static pages
  get "about", to: "pages#about"
  get "guidelines", to: "pages#guidelines"
  get "contact", to: "pages#contact"

  # Main feed
  get "feed", to: "feed#index"
  get "feed/trending", to: "feed#trending"
  get "feed/following", to: "feed#following"

  # Rooms
  resources :rooms, only: [:index, :show] do
    member do
      post :join
      delete :leave
    end
    resources :posts, only: [:index], module: :rooms
  end

  # Posts
  resources :posts do
    member do
      post :feature
      post :unfeature
    end
    resources :comments, only: [:create, :update, :destroy] do
      member do
        post :reply
      end
    end
    resource :bookmark, only: [:create, :destroy]
  end

  # Likes (polymorphic)
  post "likes/:likeable_type/:likeable_id", to: "likes#create", as: :likes
  delete "likes/:likeable_type/:likeable_id", to: "likes#destroy", as: :unlike

  # User profiles
  resources :users, only: [:show], param: :username, path: "u" do
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

  resources :resource_items, path: "resources", as: :resources_items do
    member do
      post :approve
      post :reject
    end
  end

  resources :resource_categories, only: [:index, :show]

  # Bookmarks
  get "bookmarks", to: "bookmarks#index"

  # Notifications
  resources :notifications, only: [:index] do
    collection do
      post :mark_all_read
    end
    member do
      post :mark_read
    end
  end

  # Search
  get "search", to: "search#index"

  # Settings
  namespace :settings do
    root to: "profiles#edit"
    resource :profile, only: [:edit, :update]
    resource :account, only: [:edit, :update]
    resource :notifications, only: [:edit, :update]
    resource :privacy, only: [:edit, :update]
  end

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
    resources :reports do
      member do
        post :resolve
        post :dismiss
      end
    end
    resources :moderation_logs, only: [:index, :show]
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
