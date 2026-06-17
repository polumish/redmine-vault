require File.expand_path('../../test_helper', __FILE__)

class KeysSensitiveTest < Redmine::ControllerTest
  tests KeysController
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys, :edit_keys)
    Setting.plugin_vault = { 'use_null_encryption' => true }
    @normal = Vault::Password.create!(project: @project, name: 'Normal', body: 'n', sensitive: false)
    @secret = Vault::Password.create!(project: @project, name: 'Secret', body: 's', sensitive: true)
  end

  def teardown
    Setting.plugin_vault = {}
  end

  def test_index_hides_sensitive_without_permission
    @request.session[:user_id] = 2
    get :index, params: { project_id: @project.identifier }
    assert_response :success
    assert_select 'a', text: 'Normal'
    assert_select 'a', text: 'Secret', count: 0
  end

  def test_index_shows_sensitive_with_permission
    Role.find(1).add_permission!(:view_sensitive_keys)
    @request.session[:user_id] = 2
    get :index, params: { project_id: @project.identifier }
    assert_select 'a', text: 'Secret'
  ensure
    Role.find(1).remove_permission!(:view_sensitive_keys)
  end

  def test_show_sensitive_forbidden_without_permission
    @request.session[:user_id] = 2
    get :show, params: { project_id: @project.identifier, id: @secret.id }
    assert_select 'label#plain_pass_show_' + @secret.id.to_s, count: 0
  end

  def test_update_sensitive_param_ignored_without_permission
    @request.session[:user_id] = 2
    put :update, params: { project_id: @project.identifier, id: @normal.id,
                           vault_key: { name: 'Normal', sensitive: '1' } }
    assert_equal false, Vault::Password.find(@normal.id).sensitive
  end

  def test_context_menu_hides_sensitive_body_without_permission
    sek = Vault::Password.create!(project: @project, name: 'CtxSecret', body: 'UNIQUEBODY12345', sensitive: true)
    @request.session[:user_id] = 2
    post :context_menu, params: { project_id: @project.identifier, ids: [sek.id] }
    assert_response :forbidden
    assert_not_includes response.body.to_s, 'UNIQUEBODY12345'
  end
end
