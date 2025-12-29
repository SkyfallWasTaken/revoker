Rails.application.routes.draw do
  root "revocations#new"
  resources :revocations, only: [:new, :create, :show, :edit, :update]
  post "token_types/detect" => "token_types#detect"
  get "up" => "rails/health#show", as: :rails_health_check
end
