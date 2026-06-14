Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Library authoring surface: Subjects → Lessons → Items.
  # Shallow nesting keeps deep URLs (/lessons/:id, /items/:id) flat while
  # create/index stay nested under their parent.
  resources :subjects do
    # Lesson/item lists live on the parent's show page, so no :index action.
    resources :lessons, shallow: true, except: :index do
      # Items have no standalone detail page in M1 (they live in the lesson's
      # table); skip :index and :show.
      resources :items, shallow: true, except: %i[index show]
    end
  end

  # The Library authoring surface, reachable from Today.
  get "library", to: "subjects#index", as: :library

  # Progress — the 4th destination (plan §9): honest stage distributions, an
  # upcoming-review forecast, and durability stats. Read-only, computed on
  # demand (no jobs).
  get "progress", to: "progress#show", as: :progress

  # The spaced-review loop (plan §6, §9, §10).
  #   POST   /quiz_sessions          → start a session for a scope, build & stash
  #                                     the ordered item list, land on the first card
  #   GET    /quiz_sessions/:id       → the current card (or redirect to summary)
  #   GET    /quiz_sessions/:id/summary → "N/M complete"
  #   POST   /quiz_sessions/:id/finish → end early (no penalty) → summary
  #   POST   /quiz_sessions/:id/attempts        → grade the current card, auto-advance
  #   DELETE /quiz_sessions/:id/attempts        → undo the last grade
  resources :quiz_sessions, only: %i[create show] do
    member do
      get :summary
      post :finish
    end
    resource :attempt, only: %i[create destroy]
  end

  # Authentication (plan §7). Sign-out is the DELETE on the singular session
  # resource (never a GET link). Friendly aliases for the unauthenticated shell.
  resource :session, only: %i[new create destroy]
  get  "sign_in",  to: "sessions#new"
  get  "sign_up",  to: "registrations#new"
  resource :registration, only: %i[new create]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :account, only: %i[show update destroy] do
    get :export, on: :member
  end

  # Classroom (M6). Teacher-facing cohort management + roster; the assignment
  # surface; and the student self-service membership (join-by-code / my classes).
  resources :cohorts do
    # Teacher roster management (enroll/remove a student) — owner-scoped.
    resources :enrollments, only: %i[create destroy], module: :cohorts
    # Teacher assigns/withdraws their lessons to/from this cohort (M6c).
    resources :assignments, only: %i[create destroy], module: :cohorts
    # Honest class-aggregate progress for this cohort (M6d). Pin the controller
    # name (a singular `resource` would otherwise look for ProgressesController).
    resource :progress, only: :show, controller: "cohorts/progress"
  end
  # Student self-service: my classes, join-by-code, leave.
  resources :memberships, only: %i[index create destroy]

  # Admin account & role management (plan §8.1, M6a). Admin-only (UserPolicy);
  # role changes and account deletes are audited + type-to-confirm. Admins manage
  # accounts, never learning content.
  namespace :admin do
    resources :users, only: %i[index show update destroy]
    resources :audit_events, only: :index
  end

  # Today / Home: the "Start review — N due" front door (plan §9).
  root "today#show"
end
