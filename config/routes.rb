RedmineApp::Application.routes.draw do
  namespace :admin do
    resources :webhook_endpoints do
      member do
        patch :toggle
        post :test
      end
    end
    resources :webhook_deliveries do
      member do
        post :replay
      end
      collection do
        post :bulk_replay
      end
    end
  end
end
