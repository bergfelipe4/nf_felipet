Rails.application.routes.draw do
  # Rotas Devise (removendo ROTAS DE REGISTRO normais)
  devise_for :users, skip: [:registrations]

  # Reativando REGISTRATIONS porém com caminhos customizados
 devise_scope :user do
  # signup
  get  "/segredo",       to: "devise/registrations#new",    as: :new_user_registration
  post "/segredo",       to: "devise/registrations#create", as: :user_registration

  # EDITAR PERFIL
  get "/perfil/editar",  to: "devise/registrations#edit",   as: :edit_user_registration
  put "/perfil",         to: "devise/registrations#update", as: :user_registration_update
end


  # Rotas autenticadas
  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  # Rotas não autenticadas
  devise_scope :user do
    unauthenticated do
      root to: "devise/sessions#new", as: :unauthenticated_root
    end
  end

  # Dashboard
  get "dashboard/index"
  

  # Recursos principais
  resources :notas_fiscais
  resource :certificate, only: [:new, :create, :destroy, :show]
  
  # ROTA CORINGA (para tudo que não existe)
  match "*path", to: "application#not_found", via: :all
end
