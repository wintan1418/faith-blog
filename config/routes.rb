Rails.application.routes.draw do
  # Devise authentication
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    registrations: "users/registrations",
    sessions: "users/sessions",
    passwords: "users/passwords",
    unlocks: "users/unlocks"
  }

  # Root path
  root "home#index"

  # Dynamic, accent-tinted OG image for social shares.
  get "og.svg", to: "og#show", as: :og_image, defaults: { format: :svg }
  get "sitemap.xml", to: "sitemaps#show", as: :sitemap, defaults: { format: :xml }
  # IndexNow key file (/<key>.txt); the controller 404s any other name.
  get ":indexnow_key", to: "index_now_keys#show", as: :indexnow_key, format: false,
                       constraints: { indexnow_key: /[A-Za-z0-9\-]{8,128}\.txt/ }

  # Static pages
  get "about", to: "pages#about"
  get "give", to: "giving#show", as: :give
  post "give", to: "giving#create"
  get "give/thanks", to: "giving#thanks", as: :give_thanks
  post "give/webhook", to: "giving#webhook", as: :give_webhook
  get "guidelines", to: "pages#guidelines"
  get "contact", to: "pages#contact"
  get "privacy", to: "pages#privacy"
  get "terms", to: "pages#terms"
  get "child-safety", to: "pages#child_safety", as: :child_safety

  # Main feed
  get "feed", to: "feed#index"
  get "feed/trending", to: "feed#trending"
  get "feed/following", to: "feed#following"
  get "feed/threads",   to: "feed#threads"
  get "feed/updates",   to: "feed#updates"
  get "feed/new_posts", to: "feed#new_posts", as: :feed_new_posts

  # Who's online: heartbeat from the signed-in layout, and the feed's "Online now" row.
  post "presence/ping", to: "presence#ping", as: :presence_ping
  get "presence/strip", to: "presence#strip", as: :presence_strip

  # Wall of Answered Prayers — public celebration of every answered chain.
  get "answered", to: "answered_prayers#index", as: :answered_prayers

  # Prayer Circles — private groups with a quiet stream + shared prayer list.
  # The join route must precede resources so "join" is never read as a slug.
  # The invite link shows a confirm page; joining is a POST (a GET must never
  # change state — link previews and prefetchers follow links).
  get "circles/join/:code", to: "circles#join_confirm", as: :join_circle
  post "circles/join/:code", to: "circles#join"
  resources :circles, param: :slug, only: [ :index, :show, :create, :destroy ] do
    member do
      delete :leave
      post :rotate_invite
    end
    resources :breaths, controller: "circle_breaths", only: [ :create, :destroy ]
    resources :prayers, controller: "circle_prayers", only: [ :create, :destroy ] do
      member do
        post :amen
        post :answered
      end
    end
  end

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
      get  :reactions
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

  # GIF picker (Klipy, called from the server so the key stays private).
  get "gifs", to: "gifs#index", as: :gifs, defaults: { format: :json }
  get "gifs/trending", to: "gifs#trending", as: :trending_gifs, defaults: { format: :json }

  # User profiles
  # Skill endorsements (from connections) and the digital business card.
  post "u/:username/endorse", to: "endorsements#create", as: :endorse_skill
  delete "u/:username/endorse", to: "endorsements#destroy", as: :unendorse_skill
  # Personal invite link ("Come join the conversation") and the page members share it from.
  get "join/:username", to: "joins#show", as: :join_invite, constraints: { username: %r{[^/.]+} }
  get "invite", to: "invitations#index", as: :invite_friends
  get "in/:username", to: "cards#show", as: :card, constraints: { username: %r{[^/.]+} }
  patch "in/:username/style", to: "cards#style", as: :card_style, constraints: { username: %r{[^/.]+} }

  # A piece of work on someone's Portfolio tab.
  get "u/:username/work/:id", to: "portfolio_items#show", as: :portfolio_work
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
  # Scripture pages — a living concordance: the verse + every breath that
  # carries it. Declared after /scripture/lookup so "lookup" never parses
  # as a slug.
  get "scripture/:slug", to: "scripture_pages#show", as: :scripture_page, constraints: { slug: /[a-z0-9\-]+/ }
  post "bible/search", to: "bible#search", as: :bible_search

  # Games / leaderboard
  get  "games",                  to: "games#index",            as: :games
  get  "games/quiz",             to: "games#quiz",             as: :games_quiz
  post "games/quiz/generate",    to: "games#quiz_generate",    as: :games_quiz_generate
  post "games/quiz/submit",      to: "games#quiz_submit",      as: :games_quiz_submit
  post "games/quiz/flag",        to: "games#quiz_flag",        as: :games_quiz_flag
  get  "games/chess",            to: "games#chess",            as: :games_chess
  post "games/chess/solved",     to: "games#chess_solved",     as: :games_chess_solved
  get  "games/chess/practice",   to: "games#chess_practice",   as: :games_chess_practice
  get  "games/history",          to: "games#history",          as: :games_history
  post "games/history/generate", to: "games#history_generate", as: :games_history_generate
  post "games/history/submit",   to: "games#history_submit",   as: :games_history_submit

  get  "games/character_match",          to: "games#character_match",          as: :games_character_match
  post "games/character_match/generate", to: "games#character_match_generate", as: :games_character_match_generate
  post "games/character_match/submit",   to: "games#character_match_submit",   as: :games_character_match_submit

  get  "games/reference_scramble",          to: "games#reference_scramble",          as: :games_reference_scramble
  post "games/reference_scramble/generate", to: "games#reference_scramble_generate", as: :games_reference_scramble_generate
  post "games/reference_scramble/submit",   to: "games#reference_scramble_submit",   as: :games_reference_scramble_submit

  get  "games/verse_memory",          to: "games#verse_memory",          as: :games_verse_memory
  post "games/verse_memory/generate", to: "games#verse_memory_generate", as: :games_verse_memory_generate
  post "games/verse_memory/submit",   to: "games#verse_memory_submit",   as: :games_verse_memory_submit

  get  "games/pic_word",          to: "games#pic_word",          as: :games_pic_word
  post "games/pic_word/generate", to: "games#pic_word_generate", as: :games_pic_word_generate
  post "games/pic_word/submit",   to: "games#pic_word_submit",   as: :games_pic_word_submit

  # Church History Arena — explore figures across eras
  get  "history",                to: "church_history#index",     as: :church_history
  get  "history/figure/:slug",   to: "church_history#figure",    as: :church_history_figure
  get  "history/era/:era",       to: "church_history#chronicle", as: :church_history_chronicle

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
      get  :visit
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
  # The blog (public).
  get "blog", to: "blog#index", as: :blog
  get "blog/feed.xml", to: "blog#feed", as: :blog_feed, defaults: { format: :rss }
  get "blog/:slug", to: "blog#show", as: :blog_article, constraints: { slug: /[a-z0-9-]+/ }
  # Development only: the cover art page that bin/render-blog-covers screenshots.
  get "blog/:slug/cover", to: "blog#cover", constraints: { slug: /[a-z0-9-]+/ } if Rails.env.development?

  get "people", to: "users#index", as: :people
  # "Breathers around you": members nearby who chose to be found (city level only).
  get "around", to: "around#show", as: :around
  patch "around", to: "around#update"
  get "around/city", to: "around#city", as: :city_around
  post "around/hello", to: "around#hello", as: :around_hello
  # City picker type-ahead and "Use my location" (POST, so the position never sits in a URL).
  get "cities", to: "cities#index", as: :cities, defaults: { format: :json }
  post "cities/nearest", to: "cities#nearest", as: :nearest_city, defaults: { format: :json }
  get "people/suggested", to: "users#suggested", as: :suggested_people

  # Settings
  namespace :settings do
    get "/", to: redirect("/settings/profile/edit")
    resource :profile, only: [ :edit, :update ]
    resource :account, only: [ :edit, :update, :destroy ] do
      get :delete # confirmation screen before destroy
    end
    resource :notifications, only: [ :edit, :update ]
    resource :privacy, only: [ :edit, :update ]
    resource :updates, only: [ :update ] # which Updates bots a member sees
    resource :brethren_card, only: [ :edit, :update ]
    resource :professional, only: [ :edit, :update ]
    resources :experiences, only: [ :new, :create, :edit, :update, :destroy ]
    resources :educations, only: [ :new, :create, :edit, :update, :destroy ]
    resources :certifications, only: [ :new, :create, :edit, :update, :destroy ]
    resources :languages, only: [ :create, :destroy ]
    resources :portfolio_items, except: [ :show ] do
      patch :move, on: :member
    end
    resource :linkedin_import, only: [ :new, :create ] do
      post :apply
    end
    resource :dark_mode, only: [ :update ]
    resource :accent,    only: [ :edit, :update ]
    resource :background_rain, only: [ :update ]
  end

  # Brethren Card & Connection Requests
  resources :brethren_cards, only: [ :show ], param: :username
  resources :suggestion_dismissals, only: [ :create ]
  resources :connection_requests, only: [ :index, :create ] do
    member do
      post :accept
      post :decline
    end
  end
  get "my-connections", to: "connection_requests#connections", as: :my_connections

  get "inbox/search", to: "conversations#search", as: :inbox_search
  get "unread_counts", to: "unread_counts#show", as: :unread_counts
  resources :conversations, path: "inbox", only: [ :index, :show, :new, :create ] do
    member do
      post :archive
      post :mark_read
      get :earlier
    end
    resources :messages, only: [ :create, :update, :destroy ] do
      member do
        get :forward, action: :pick_forward # choose chats to forward to
        post :forward
      end
      # A file from the message, saved under its original name (participants only).
      # The name in the URL is only for the phone's download list; the id decides.
      get "files/:id/:filename", to: "message_files#show", as: :file, format: false, constraints: { filename: %r{[^/]+} }
    end
  end
  resources :message_blocks, only: [ :create, :destroy ], param: :user_id

  # "Get the app" waitlist on the welcome page (open to signed-out visitors).
  post "waitlist", to: "app_waitlist_entries#create", as: :waitlist

  # Admin namespace
  namespace :admin do
    root to: "dashboard#index"
    resources :app_waitlist_entries, only: :index, path: "app-waitlist"
    resources :city_changes, only: :index, path: "city-changes"
    get "online", to: "online#index", as: :online
    get "bots", to: "bots#index", as: :bots
    resource :seo, only: :show, controller: "seo", path: "seo" do
      post :refresh
      post :sitemap
      post :inspect_url, path: "inspect"
      post :index_now, path: "indexnow"
    end
    resource :push_test, only: [ :show, :create ], path: "push-test"
    resource :app_release, only: [ :edit, :update ], path: "app-versions" do
      post :remind
    end
    post "bots/refresh", to: "bots#refresh", as: :refresh_bots
    patch "bots/sources/:id/toggle", to: "bots#toggle_source", as: :toggle_bot_source
    patch "bots/items/:id/toggle", to: "bots#toggle_item", as: :toggle_bot_item
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
        post :retire_question
      end
    end
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
      collection do
        post :release_post
      end
    end
    resources :broadcasts do
      member do
        post :send_now
      end
    end
    resources :announcements, only: [ :index, :new, :create, :destroy ]

    # The Office: the founder's AI assistant.
    get "office", to: "office/conversations#index", as: :office
    namespace :office do
      resources :conversations, only: [ :show, :create, :update, :destroy ] do
        collection { post :import }
        member do
          post :retry
          get :refresh
        end
        resources :messages, only: [ :create ]
      end
      resources :cards, only: [] do
        member do
          patch :update_breath
          post :post_breath
          post :use_in_breath
          post :publish_announcement
          get :image_picker
          post :attach_image
          post :remove_image
          get :breath_picker
          post :add_to_breath
        end
      end
      resource :briefing, only: [ :show, :update ]
    end
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

  # Mobile apps (Hotwire Native)
  post   "push_devices", to: "push_devices#create",  as: :push_devices
  delete "push_devices", to: "push_devices#destroy"

  # Native Google sign-in for the mobile apps (see Users::NativeGoogleSessionsController)
  get  "auth/google/native/start", to: "users/native_google_sessions#start", as: :native_google_start
  post "auth/google/native",       to: "users/native_google_sessions#create", as: :native_google_sign_in
  # Sign in with Apple for the iPhone app (see Users::NativeAppleSessionsController)
  get  "auth/apple/native/start",  to: "users/native_apple_sessions#start", as: :native_apple_start
  post "auth/apple/native",        to: "users/native_apple_sessions#create", as: :native_apple_sign_in

  get ".well-known/assetlinks.json", to: "well_known#assetlinks", defaults: { format: :json }
  get ".well-known/apple-app-site-association", to: "well_known#apple_app_site_association", defaults: { format: :json }
  get "apple-app-site-association", to: "well_known#apple_app_site_association", defaults: { format: :json }
  post "whats_new/:id/seen", to: "whats_new#seen", as: :seen_whats_new

  # Seeds: engagement points and ranks.
  get  "leaderboard", to: "leaderboard#index", as: :leaderboard
  get  "seeds", to: "seeds#show", as: :seeds_guide
  post "seeds/rank_seen", to: "seeds#rank_seen", as: :seeds_rank_seen
  post "dismissals", to: "dismissals#create", as: :dismissals
  # First-run onboarding: hide or bring back the getting-started list; finish or retake the tour.
  scope "onboarding", controller: "onboarding", as: "onboarding" do
    post "hide", action: :hide, as: :hide
    get "checklist", action: :checklist, as: :checklist
    post "show", action: :show_checklist, as: :show
    post "tour/finish", action: :finish_tour, as: :finish_tour
    post "tour/restart", action: :restart_tour, as: :restart_tour
  end
  get "me", to: "me#show", as: :me
  get "configurations/ios_v1.json",     to: "configurations#ios_v1",     defaults: { format: :json }
  get "configurations/android_v1.json", to: "configurations#android_v1", defaults: { format: :json }

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
  # "Update the app" alerts land here and go straight to the Play Store listing.
  get "app/update", to: redirect("https://play.google.com/store/apps/details?id=com.brethreign.app", status: 302), as: :app_update_store
end
