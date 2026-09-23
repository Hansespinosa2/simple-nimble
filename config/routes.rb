Rails.application.routes.draw do
  get "spells", to: "spells#index"
  get "spells/:id", to: "spells#show", as: "spell"
  resources :characters do
    member do
      post :finalize
      patch :tracker
      patch :safe_rest
      get :history
    end
    resources :level_ups, only: %i[new create show update]
    resources :shares, only: %i[create destroy], controller: "character_shares"
  end
  resources :campaigns, only: %i[index new create show] do
    member do
      post :join
      delete :leave
    end
  end
  post "campaigns/join", to: "campaigns#join_by_code", as: :join_campaign_by_code
  resources :sessions, only: %i[new create destroy]
  get "shared/:token", to: "shared_characters#show", as: :shared_character
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "characters#index"
end
