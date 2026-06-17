require File.expand_path('../../test_helper', __FILE__)

class VaultKeyVersionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    User.current = User.find(1) # admin
  end

  def test_model_and_association_load
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    assert_equal 0, k.vault_key_versions.count
    v = k.vault_key_versions.create!(name: 'n', body: BodyCipher.encrypt('old'),
                                     changed_fields: 'body', changed_at: Time.current)
    assert_equal 'old', v.decrypted_body
    assert_equal ['body'], v.changed_field_list
  end

  def test_versions_destroyed_with_key
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    v = k.vault_key_versions.create!(changed_fields: 'body', changed_at: Time.current)
    k.destroy
    assert_nil Vault::KeyVersion.find_by(id: v.id)
  end
end
