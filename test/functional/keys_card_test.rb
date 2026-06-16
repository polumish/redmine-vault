require File.expand_path('../../test_helper', __FILE__)

class KeysCardTest < Redmine::ControllerTest
  tests KeysController
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys)
    @key = Vault::Key.create!(project: @project, name: 'DB root', type: 'Vault::Password',
                              login: 'root', body: 's3cret', whitelist: '')
  end

  def test_card_renders_detail_partial_for_whitelisted
    @request.session[:user_id] = 1 # admin sees all
    get :card, params: { project_id: @project.identifier, id: @key.id }
    assert_response :success
    assert_select 'div.vault-card'
    assert_match 'root', response.body          # login shown
    refute_match(/<body|id="main-menu"/, response.body) # no layout
  end

  def test_card_forbidden_for_non_whitelisted
    Role.find(1).add_permission!(:view_keys, :whitelist_keys)
    @key.update_column(:whitelist, '99')        # group/user 99, not user 2
    @request.session[:user_id] = 2              # jsmith, non-admin, member of project 1
    get :card, params: { project_id: @project.identifier, id: @key.id }
    assert_response :forbidden
  end

  def test_card_missing_key_404
    @request.session[:user_id] = 1
    get :card, params: { project_id: @project.identifier, id: 999999 }
    assert_response :missing
  end
end
