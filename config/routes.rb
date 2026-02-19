Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resource :me, only: [:show, :update], controller: "me"
      resource :profile, only: [:show, :update], controller: "profile"

      resources :conversations do
        member do
          get :report
        end

        resources :messages, only: %i[index create] do
          collection do
            post :respond_last_interviewer
          end
        end
        resources :captions, only: %i[create] do
          collection do
            post :stream, to: "captions#create_stream"
          end
        end
      end

      namespace :auth do
        post "register", to: "registrations#create"
        post "login",    to: "sessions#create"
        get "verify",    to: "sessions#verify"
      end
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
