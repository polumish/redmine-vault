require File.expand_path('../../test_helper', __FILE__)

class VaultPasswordLinkTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys, :whitelist_keys)
  end

  def test_not_found
    User.current = User.find(1)
    assert_equal :not_found, Vault::PasswordLink.resolve(99999)[:state]
  end

  def test_ok_for_admin
    User.current = User.find(1) # admin -> always whitelisted
    key = Vault::Key.create!(project: @project, name: 'k-ok', type: 'Vault::Password', whitelist: '')
    res = Vault::PasswordLink.resolve(key.id)
    assert_equal :ok, res[:state]
    assert_equal key.id, res[:key].id
  end

  def test_no_access_when_not_whitelisted
    User.current = User.find(2) # jsmith, member of project 1, has whitelist_keys via role
    key = Vault::Key.create!(project: @project, name: 'k-na', type: 'Vault::Password', whitelist: '99999')
    assert_equal :no_access, Vault::PasswordLink.resolve(key.id)[:state]
  end

  def test_no_access_for_sensitive_without_permission
    Role.find(1).add_permission!(:view_keys)
    Role.find(1).remove_permission!(:view_sensitive_keys)
    User.current = User.find(2)
    key = Vault::Password.create!(project: @project, name: 'sek', type: 'Vault::Password', sensitive: true, whitelist: '')
    assert_equal :no_access, Vault::PasswordLink.resolve(key.id)[:state]
  end
end
