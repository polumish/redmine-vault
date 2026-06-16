resources :projects do
  match '/keys/context_menu', to: 'keys#context_menu', as: 'keys_context_menus', via: [:get, :post]
  get '/keys/picker', to: 'keys#picker', as: 'keys_picker'
  resources :keys
  get '/key_files/:id/download', to: 'key_files#download', as: 'download_key_file'
  get '/key_files/:id/preview', to: 'key_files#preview', as: 'preview_key_file'
  get '/key_attachments/:id/download', to: 'key_attachments#download', as: 'download_key_attachment'
  get '/key_attachments/:id/preview', to: 'key_attachments#preview', as: 'preview_key_attachment'
  get '/keys/:id/copy', to: 'keys#copy', as: 'copy_key'
  get '/keys/:id/card', to: 'keys#card', as: 'card_key'
end

resources :vault_settings do
  collection do
    get :autocomplete_for_user
    post :backup, to: 'vault_settings#backup'
    post :restore, to: 'vault_settings#restore'
    post :save, to: 'vault_settings#save'
  end
end
