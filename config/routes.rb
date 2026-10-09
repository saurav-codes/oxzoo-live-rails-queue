Rails.application.routes.draw do
  root "status#index"
  get "up" => "rails/health#show", as: :rails_health_check
  get "api/hops" => "status#hops"
  get "api/queue" => "status#queue"
  post "webhooks/zoo" => "webhooks#create"

  scope "_zoo", controller: :zoo do
    get "health"
    get "probe"
    get "verify"
    get "trace/:id", action: :trace
    match "*path", action: :preflight, via: :options
  end
end
