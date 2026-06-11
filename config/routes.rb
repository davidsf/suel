Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  root "game_modules#index"

  resources :game_modules, only: %i[index show], param: :slug do
    get "assets/*path", to: "module_assets#show", as: :asset, format: false
    get :palette, to: "palettes#show"
    resources :boards, only: :show
    resources :scenarios, only: :show
  end

  namespace :admin do
    resources :game_modules, only: %i[new create destroy], param: :slug do
      member do
        post :reimport
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
