require File.expand_path('../../test_helper', __FILE__)

class VaultSensitiveTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys)
  end

  def test_non_sensitive_is_viewable_with_view_keys
    User.current = User.find(2)
    k = Vault::Password.create!(project: @project, name: 'n1', sensitive: false)
    assert k.viewable?(@project)
  end

  def test_sensitive_hidden_without_permission
    Role.find(1).remove_permission!(:view_sensitive_keys)
    User.current = User.find(2)
    k = Vault::Password.create!(project: @project, name: 's1', sensitive: true)
    refute k.viewable?(@project)
  end

  def test_sensitive_visible_with_permission
    Role.find(1).add_permission!(:view_sensitive_keys)
    User.current = User.find(2)
    k = Vault::Password.create!(project: @project, name: 's2', sensitive: true)
    assert k.viewable?(@project)
  ensure
    Role.find(1).remove_permission!(:view_sensitive_keys)
  end

  def test_admin_sees_sensitive
    User.current = User.find(1)
    k = Vault::Password.create!(project: @project, name: 's3', sensitive: true)
    assert k.viewable?(@project)
  end
end
