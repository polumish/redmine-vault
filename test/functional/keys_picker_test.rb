require File.expand_path('../../test_helper', __FILE__)

class KeysPickerTest < Redmine::ControllerTest
  tests KeysController
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys)
    @request.session[:user_id] = 1 # admin sees all
    Vault::Key.create!(project: @project, name: 'Zeta',  type: 'Vault::Password', whitelist: '')
    Vault::Key.create!(project: @project, name: 'Alpha', type: 'Vault::Password', whitelist: '')
  end

  def test_picker_returns_sorted_id_name_only
    get :picker, params: { project_id: @project.identifier }
    assert_response :success
    data = JSON.parse(response.body)
    assert data.is_a?(Array)
    assert_equal %w[Alpha Zeta], data.map { |h| h['name'] }
    assert_equal %w[id name], data.first.keys.sort
    refute data.first.key?('body')
  end
end
